## Goal

Build a matrix-multiply accelerator in SystemVerilog, implemented at three points on
the area/throughput curve, verified in simulation and characterized on real silicon.
The progression is the deliverable: each version addresses a concrete limitation of
the previous one.

---

## Phase 1 — Sequential baseline

Single MAC unit, N^3 cycles, matrices held in register arrays. AXI4-Stream slave for
loading, AXI4-Stream master for results.

**D-01: Stream results as computed rather than buffering the output matrix.** The
sequential design produces C elements serially in row-major order, which is already
the output order, so no output buffer is needed.

**D-02: Counter width needs an overflow bit.** `load_cnt` sized
`[$clog2(2*N*N)-1:0]` wraps at 2N^2-1 and never reaches the terminal count.
Corrected to `[$clog2(2*N*N):0]`. Applied to every terminal-count comparison
thereafter.

**Verification.** cocotb + Icarus with a Python golden model, 100 randomized trials.
Randomized per-cycle backpressure on the output stream: the collected result must be
bit-identical regardless of stall pattern.

**Learned: testbench edge discipline.** Drive inputs before the clock edge (the DUT
samples at the edge), read outputs after (they reflect that edge). Both must
reference the same edge or the handshake check describes two different cycles. This
is the testbench-side shadow of non-blocking read-old/write-new.

---

## Phase 2 — Systolic array (register storage)

N x N grid of output-stationary processing elements. Each PE owns one output element
and performs one MAC per cycle; A flows left-to-right, B flows top-to-bottom.

**D-03: Register the PE passthroughs rather than wiring them combinationally.** The
one-cycle-per-hop delay *is* the skew that makes matching operands rendezvous at the
correct PE. Correct global timing emerges from a purely local rule, with no central
scheduler — which is why the architecture scales.

**D-04: Skew schedule.** `a_edge[i] = A[i][t-i]` when `0 <= t-i < N`, else 0;
`b_edge[j] = B[t-j][j]` likewise. Row i delayed i cycles, column j delayed j.
Padding cycles feed zero, so the accumulator is unaffected.

**BUG: unsigned subtraction wraparound.** The naive window check
`t-i >= 0 && t-i < N` is broken for unsigned counters — the first condition is always
true and `t-i` wraps to a large value when `i > t`. Fixed by testing `t >= i` first,
which guards the subtraction.

**BUG: array accumulated during the load phase.** The combinational feed was live
whenever `t` was valid, including while matrices were streaming in, so PE(0,0)
summed extra terms. Fixed by gating the feed on `compute_busy`.

**BUG: registered output skewed the stream.** Back-to-back streaming exposed a
one-cycle lag between the registered `tdata`/`tvalid` and the counter driving them,
producing a duplicated first beat and a shifted result. The sequential version never
hit this because it produced results with gaps.

**D-05: Keep the output registered and fix the advance logic** rather than driving it
combinationally. Registered outputs give a clean timing boundary for closure. The
pattern: `tvalid` doubles as a slot-full flag; the register loads the next element
only when the current beat is accepted, and holds otherwise. `out_cnt` consequently
means "next element to load" and leads by one.

**D-06: Detect completion via `tlast` transferring**, not by counting, tying
end-of-operation to the protocol's own last-beat marker.

**Learned: latency is ~3N.** PE(i,j) takes its last term at cycle `i + j + (N-1)`;
the bottom-right corner dominates at `3(N-1)`. Three ~N contributions: skew ramp-in,
propagation to the far corner, accumulation.

---

## Phase 3 — Banked memory

Operand storage moved from flip-flops into a banked memory array so the design scales
beyond what register arrays permit.

**D-07: Infer memory via a synchronous read** (`rdata <= mem[raddr]` inside
`always_ff`). A combinational read infers a different primitive. The memory array is
deliberately not reset — resetting it defeats block-RAM inference, and it is
unnecessary because memory is write-before-read.

**D-08: Bank by access pattern.** One memory has one read port and yields one value
per cycle, but the systolic feed needs N per cycle. Storage is split into
independently addressed banks — A by row, B by column — read in parallel. The
required bandwidth dictates the banking.

**D-09: Pipeline the feed around the one-cycle read latency.** Three blocks: present
addresses per the skew schedule; register a valid flag so it arrives with the late
data; mask out-of-window reads to zero.

**BUG: prefetching with `t+1` dropped the first diagonal.** Its address would have
needed presenting at `t = -1`. Fixed by presenting diagonal `t`'s address at cycle
`t`; the array consumes it at `t+1`, shifting the whole timeline one cycle later,
absorbed by the drain threshold.

---

## Phase 4 — Generalization to MxN * NxK

**D-10: Generalize only the banked version.** The other two remain square as
documented baselines; generalizing a non-scaling design adds nothing.

Three independent parameters: M = grid rows, K = grid columns, N = contraction length
(MACs per PE). The PE is unchanged. Drain becomes `M+K+N-3`, derived from
`i+j+(N-1)` at the bottom-right PE.

**Dimension traps:** the feed window length is always N (the contraction), not the
grid size; the output stride is K, not N; B is banked over K where A is over N.
Square case M=N=K retained as a regression guard.

---

## Phase 5 — Deployment preparation

**D-11: Remove the `ops_val`/`ops_rdy`/`res_val`/`res_rdy` sideband.** It was a
non-standard bolt-on with no driver on a DMA-fed system — AXI DMA drives only
`tdata`/`tvalid`/`tready`/`tlast`. All three versions are now pure AXI4-Stream
blocks: push M*N + N*K bytes in, receive M*K results out framed by `tlast`.

**D-12: Add a per-operation `clear` distinct from `rst`.** The design was
single-shot: PE accumulators, `load_cnt`, and `compute_done` persisted across
operations, so operation two accumulated on top of operation one. Reset is
infrastructure (asserted once at bringup); clear is functional (asserted between
operations). Control emits a one-cycle Mealy pulse on the COMPUTE -> LOAD transition;
the datapath reinitializes its counters and the pulse is threaded down to every PE.

Memory contents are deliberately not cleared — write-before-read means the next
operation overwrites everything it will read.

**D-13: Self-sequencing control.** Two states. LOAD advances to COMPUTE on `loaded`;
COMPUTE returns to LOAD on `compute_done`, pulsing `clear`. No external start signal,
so the block runs continuously under DMA.

**Verification change: reset once, then run 100 back-to-back operations.** The
previous per-trial reset masked all of the above — it is not a condition the board
can reproduce.

**Repo restructured** into `<version>/rtl/` and `<version>/tb/`, plus a shared
`fpga/` for constraints, scripts, and results.

---

## Phase 6 — FPGA characterization

Out-of-context synthesis and implementation on Xilinx Zynq UltraScale+ (XCZU7EV-2),
Vivado 2019.2, scripted in TCL and swept across three architectures at N = 4…64.

**D-14: Out-of-context synthesis.** The accelerator is intended as a DMA-fed block,
not a pinned-out top-level design, so OOC is the right methodology — it skips I/O
buffer insertion and pin assignment rather than inventing an arbitrary pin mapping
that would distort boundary timing. Fmax is derived from worst negative slack against
an aggressive 500 MHz constraint, so one run per configuration suffices instead of
binary-searching the clock period.

**D-15: Consume `s_axis_tlast` as a frame-integrity check.** Loading completion is
counter-driven, so `tlast` was declared but unused — Vivado flagged the unconnected
port. Cross-checking it against the expected final beat latches `frame_error` when
the sender's frame boundary disagrees with the internal count, turning a dropped or
extra beat from silent data corruption into a visible flag.

The check immediately caught a testbench bug: `tlast` was asserted at the end of
*each matrix* rather than at the end of the frame (A followed by B). The RTL was
correct; the stimulus was not — exactly the class of silent protocol mismatch the
check exists to expose.

A second bug followed: `frame_error` was initially cleared in the per-operation
`clear` branch rather than in `rst`, leaving it undefined from power-on and wiping
any error at the start of the next operation. Corrected to reset only on `rst`. This
reinforces the reset/clear split from D-12 — `clear` reinitializes per-operation
state, `rst` initializes everything, and sticky error flags belong only to the latter.

**D-16: Measured, then rejected, forced block-RAM inference.** Synthesis maps the
operand banks to LUTRAM by default. Overriding with `ram_style = "block"` confirms
the banking architecture maps cleanly onto real memory primitives (BRAM count is
exactly 2N, one per bank) but costs 24–89 MHz at every size and *increases* LUT count
at N<=8. A bank holds only N words of 8 bits against an 18 kbit RAMB18, so the blocks
are under 1% utilized and the fabric savings never materialize, while the fixed
column placement of block RAM lengthens the operand path and adds read setup delay.
Kept the default mapping; retained both datasets since the comparison is itself the
result.

**Findings.** systolic_bram dominates systolic_reg on both area and frequency at
N>=8. Fmax degrades monotonically with N across all three architectures. Both
systolic variants exceed device capacity at N=64, requiring ~464k LUTs against
230,400 available; synthesis completes but placement fails DRC on over-utilization.
That both fail identically shows the design is compute-bound rather than
storage-bound — the N^2 PE count dominates area, so banking improves efficiency
without moving the capacity ceiling. No DSP inference at WIDTH=8.

---

## Open

- Deploy to hardware: package as IP, build a block design with the Zynq PS and AXI
  DMA, and measure end-to-end throughput. Currently blocked on board access.
- Explore deeper banks (larger WIDTH or tiled operands) where block RAM would become
  the better mapping.
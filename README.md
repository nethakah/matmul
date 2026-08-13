# Parameterized Matrix-Multiply Accelerator (SystemVerilog)

A hardware matrix-multiply accelerator implemented three ways, each addressing the
limitations of the previous one. All three expose an identical AXI4-Stream interface,
are verified in simulation with [cocotb](https://www.cocotb.org/) under randomized
backpressure, and are characterized through synthesis and implementation on a Xilinx
Zynq UltraScale+ device.

The three implementations — **sequential -> systolic -> systolic + banked memory** —
solve the same problem at three points on the area/throughput/scalability curve. The
final version generalizes to arbitrary MxN * NxK products.

---

## Architectures

| Version | Compute units | Compute latency | Operand storage | Dimensions |
|---|---|---|---|---|
| `sequential/` | 1 MAC | ~N^3 cycles | registers | NxN |
| `systolic_reg/` | N^2 PEs | ~3N cycles | registers | NxN |
| `systolic_bram/` | M*K PEs | ~M+N+K cycles | banked memory | MxN * NxK |

- **`sequential/`** — a single multiply-accumulate unit computes one output element at
  a time over N^3 cycles. Minimal area, lowest throughput. The baseline.
- **`systolic_reg/`** — an NxN grid of processing elements (output-stationary
  dataflow). A flows left-to-right, B flows top-to-bottom; each PE owns one output
  element and performs one MAC per cycle.
- **`systolic_bram/`** — the systolic array with operand storage moved out of the
  register fabric into independently addressed banks, generalized to arbitrary
  MxN * NxK products.

Parameters: `M` (rows of A / grid rows), `N` (shared/contraction dimension = MACs per
PE), `K` (columns of B / grid columns), and `WIDTH` (bits per element). The square
case M = N = K recovers the original NxN design.

---

## Interface

Identical across all three versions, which is why the testbench is shared with
minimal changes.

- **Load (AXI4-Stream slave, `s_axis_*`)** — matrices stream in element-by-element,
  row-major: all of A, then all of B. `tlast` marks the final beat of the frame.
- **Result (AXI4-Stream master, `m_axis_*`)** — output elements stream out row-major,
  one per handshake, with `tlast` on the final beat.
- **`frame_error`** — sticky flag raised if the sender's `tlast` disagrees with the
  expected element count.

The design is self-sequencing: computation starts automatically once a full frame has
been loaded, and the block returns to accepting data after the last result transfers.
No external start signal, so it drops directly into a DMA-fed system.

The output master holds data stable under backpressure (registered output, advances
only on an accepted transfer).

---

## Module hierarchy

```
chip            top: AXI4-Stream slave and master
|-- datapath    operand storage, edge feeding, result streaming
|   `-- array   the PE grid + interconnect          (systolic versions)
|       `-- pe  one processing element (MAC + passthrough registers)
`-- control     FSM: LOAD -> COMPUTE -> LOAD, emitting a per-operation clear pulse
```

---

## Systolic dataflow

For an MxN * NxK product the array is an M (rows) by K (columns) grid of PEs; each PE
performs N multiply-accumulates over the shared dimension. (Shown 3x3 for clarity.)

```
                 Matrix B streams DOWN (skewed by column)

           b_edge[0]   b_edge[1]   b_edge[2]
               |           |           |
               v           v           v
a_edge[0] --> +-----+ --> +-----+ --> +-----+
(A row 0)     |PE 00|     |PE 01|     |PE 02|
              +-----+     +-----+     +-----+
               |           |           |
               v           v           v
a_edge[1] --> +-----+ --> +-----+ --> +-----+
(A row 1)     |PE 10|     |PE 11|     |PE 12|
              +-----+     +-----+     +-----+
               |           |           |
               v           v           v
a_edge[2] --> +-----+ --> +-----+ --> +-----+
(A row 2)     |PE 20|     |PE 21|     |PE 22|
              +-----+     +-----+     +-----+

Matrix A streams RIGHT (skewed by row)
```

Each PE performs one MAC per cycle (`acc += a_in * b_in`) and registers its
passthroughs (`a_in -> a_out` rightward, `b_in -> b_out` downward), so each hop costs
one cycle. PE(i,j) accumulates C[i][j].

Inputs are skewed — A row i enters i cycles late, B column j enters j cycles late — so
the matching terms of each dot product meet at the right PE on the right cycle. The
skew is a physical consequence of the per-hop register delay, not a scheduled signal,
which is why the array scales: communication is nearest-neighbour only. The last PE
finishes at ~M+N+K cycles.

---

## Building and testing

Requires Icarus Verilog and cocotb.

```
cd systolic_bram      # or sequential/ or systolic_reg/
make
```

Each `make` runs 100 trials of random matrices with randomized per-cycle backpressure
on the output stream, checked against a Python golden model. The DUT is reset once,
then all 100 operations run back-to-back — the condition a DMA-fed system imposes.

---

## Results

Out-of-context synthesis and implementation on Xilinx Zynq UltraScale+
(XCZU7EV-2, ZCU104), Vivado 2019.2, scripted in TCL. Fmax derived from worst negative
slack against a 500 MHz constraint. Square configurations (M=N=K) to isolate scaling.

| N | sequential | systolic_reg | systolic_bram |
|---|---|---|---|
| | LUT / FF / Fmax | LUT / FF / Fmax | LUT / FF / Fmax |
| 4 | 422 / 316 / 334 MHz | 1,982 / 801 / 389 MHz | 1,988 / 595 / 350 MHz |
| 8 | 710 / 1,105 / 328 MHz | 7,547 / 3,268 / 351 MHz | 7,408 / 2,322 / **398 MHz** |
| 16 | 1,993 / 4,243 / 260 MHz | 29,740 / 13,336 / 305 MHz | 28,860 / 9,333 / 359 MHz |
| 32 | 7,348 / 16,709 / 214 MHz | 121,739 / 54,176 / 238 MHz | 116,305 / 38,199 / 276 MHz |
| 64 | 26,882 / 66,239 / 178 MHz | exceeds device | exceeds device |

**Banking wins on both axes.** systolic_bram uses fewer LUTs and ~30% fewer
flip-flops than systolic_reg at every N>=8 (38,199 vs 54,176 at N=32) while closing
at a higher frequency. Moving operands out of the register fabric frees flip-flops
and shortens critical paths.

**Fmax degrades monotonically with size** across all three architectures as routing
pressure grows. The sequential design falls hardest (334 -> 178 MHz): its operand
storage and output muxing scale as N^2 even though its compute does not.

**Device capacity is reached at N=64.** Both systolic variants require ~464k LUTs
against 230,400 available (2.0x) and 36,868 CARRY8 against 28,800. Synthesis
completes; placement fails DRC on over-utilization. Both fail *identically*, which
shows the design is compute-bound rather than storage-bound — the N^2 PE count
dominates area, so banking improves efficiency without moving the ceiling.

### Memory primitive selection

Synthesis maps the operand banks to distributed RAM (LUTRAM) by default. Forcing
block RAM with `ram_style = "block"` confirms the banking architecture maps cleanly
onto real memory primitives — BRAM count is exactly 2N, one per bank — but is a net
loss at these dimensions (raw data in `fpga/results/forced_bram/`):

| N | default (LUTRAM) | forced BRAM | Fmax delta |
|---|---|---|---|
| 4 | 1,988 LUT, 0 BRAM, 350.4 MHz | 2,145 LUT, 8 BRAM, 307.2 MHz | -43 MHz |
| 8 | 7,408 LUT, 0 BRAM, 398.2 MHz | 7,607 LUT, 16 BRAM, 308.8 MHz | -89 MHz |
| 16 | 28,860 LUT, 0 BRAM, 358.8 MHz | 28,640 LUT, 32 BRAM, 289.9 MHz | -69 MHz |
| 32 | 116,305 LUT, 0 BRAM, 276.2 MHz | 116,101 LUT, 64 BRAM, 252.7 MHz | -24 MHz |

A bank holds N words of 8 bits — 128 bits at N=16, against an 18 kbit RAMB18 — so
each block is under 1% utilized and the LUT savings never materialize. At N<=8 area
actually increases, since the block-RAM address and control logic outweighs the
storage removed from the fabric. Timing degrades at every size: block RAM sits in
fixed columns, lengthening the operand path to the array edge, and has greater read
setup delay than LUTRAM. The default heuristic is correct here; the banking
architecture would only pay off in block RAM with substantially deeper banks.

**No DSP inference at WIDTH=8.** Vivado maps 8x8 multiplies to LUT and CARRY8 logic
rather than DSP48E2 slices; wider operands would be needed for a DSP to be worthwhile.

Correctness is verified in simulation across arbitrary MxN * NxK dimensions; PPA is
characterized on square configurations to isolate scaling. Out-of-context mode omits
I/O buffer insertion and pin assignment, so boundary-path timing is approximate — the
reported critical paths are internal to the PE array, so Fmax is unaffected.

Reproduce a single configuration:

```
vivado -mode batch -source fpga/scripts/run_ooc.tcl -tclargs systolic_bram 8
```

---

## Design notes

**Output-stationary systolic dataflow.** Each PE permanently owns one output element
and accumulates one product per cycle. Operands are skewed so the matching terms of
each dot product arrive together. The skew is created physically by each PE
registering its passthroughs (one cycle per hop), so correct global timing emerges
from a purely local rule — which is why systolic arrays scale: communication is
nearest-neighbour only, so wire length stays constant as the array grows.

**Compute latency ~M+N+K.** PE(i,j) takes its last term at cycle `i + j + (N-1)`,
maximized at the bottom-right corner: `(M-1) + (K-1) + (N-1)`. Three contributions:
skew ramp-in, propagation to the far corner, and accumulation along the shared
dimension.

**Registered AXI master under backpressure.** Output `tdata`/`tvalid`/`tlast` are
registered for a clean timing boundary. `tvalid` doubles as a "slot full" flag; the
output register advances only on an accepted transfer and otherwise holds, which
makes backpressure correct by construction.

**Reset versus clear.** `rst` is infrastructure, asserted once at bringup. `clear` is
a one-cycle functional pulse emitted on the COMPUTE -> LOAD transition that
reinitializes per-operation state — counters and every PE accumulator — so
back-to-back operations do not accumulate on top of each other. Memory contents are
deliberately not cleared, since they are fully overwritten by the next load. Sticky
error flags such as `frame_error` reset only on `rst`.

**Banking by access pattern.** A single memory has one read port and yields one value
per cycle, but the systolic feed needs one value per grid row of A and per grid column
of B each cycle. Storage is split into independently addressed banks — A by row, B by
column — read in parallel. The required bandwidth dictates the banking.

**Synchronous-read latency.** The banked memory returns data one cycle after the
address is presented, so the operand feed is pipelined: present each bank's address
per the skew schedule, carry a registered valid flag so it lines up with the
late-arriving data, and mask out-of-window reads to zero.

**Generalizing to MxN * NxK.** The PE is unchanged; only dimensions are
parameterized. The grid becomes M rows by K columns; each PE accumulates N terms. The
feed active-window length is the shared dimension N (not the grid size); the output
stream stride is K (the output row length); and A and B are banked by row and column
respectively over their own inner dimensions.

---

## Verification

- Python golden model (`golden_model.py`) — reference triple-nested matrix multiply.
- 100 randomized trials per run with random per-cycle backpressure on the output
  stream; a single reset at start, then all operations back-to-back.
- `frame_error` asserted low on every trial, checking the sender's `tlast` against the
  internal element count.
- Timeouts on all wait loops, so a stalled handshake fails as a located error rather
  than hanging.

---

## Roadmap

- [ ] Deploy to hardware: package as IP, build a block design with the Zynq PS and AXI
      DMA, measure end-to-end throughput.
- [ ] Explore deeper banks (wider elements or tiled operands) where block RAM becomes
      the better mapping.
- [ ] Edge-case tests: identity, all-max-value (accumulator-width stress), all-zeros.
# Parameterized Matrix-Multiply Accelerator (SystemVerilog)

A hardware matrix-multiply accelerator implemented three ways, each addressing the
limitations of the previous one. All three expose an identical AXI4-Stream interface
and are verified in simulation with [cocotb](https://www.cocotb.org/) under randomized
backpressure.

The three implementations — **sequential -> systolic -> systolic + BRAM** — solve the
same problem at three points on the area/throughput/scalability curve. The final version
generalizes to arbitrary MxN * NxK products.

---

## Architectures

| Version | Compute units | Compute latency | Operand storage | Dimensions | Scales to large size? |
|---|---|---|---|---|---|
| `sequential/` | 1 MAC | ~N^3 cycles | registers | NxN | no |
| `systolic_reg/` | N^2 PEs | ~3N cycles | registers | NxN | no (storage) |
| `systolic_bram/` | M*K PEs | ~M+N+K cycles | banked BRAM | MxN * NxK | yes |

- **`sequential/`** — a single multiply-accumulate unit computes one output element at a
  time over N^3 cycles. Minimal area, lowest throughput. The baseline.
- **`systolic_reg/`** — an NxN grid of processing elements (output-stationary dataflow).
  A flows left-to-right, B flows top-to-bottom; each PE owns one output element and
  performs one MAC per cycle. ~N-times-or-better speedup for N^2 the multipliers.
- **`systolic_bram/`** — the systolic array with operand storage moved from flip-flops
  into banked block RAM, generalized to arbitrary MxN * NxK products. Scales to large
  matrices where register storage is infeasible.

Parameters: `M` (rows of A / grid rows), `N` (shared/contraction dimension = MACs per PE),
`K` (columns of B / grid columns), and `WIDTH` (bits per element). The square case
M = N = K recovers the original NxN design.

---

## Interface

Identical across all three versions, which is why the testbench is shared with minimal
changes.

- **Load (AXI4-Stream slave, `s_axis_*`)** — matrices stream in element-by-element,
  row-major: all of A, then all of B.
- **Result (AXI4-Stream master, `m_axis_*`)** — the output elements stream out row-major,
  one per handshake, with `tlast` on the final beat.
- **Operation handshake (`ops_val`/`ops_rdy`, `res_val`/`res_rdy`)** — ready/valid
  pair framing each matrix-multiply operation.

The output master holds data stable under backpressure (registered output, advances
only on an accepted transfer).

---

## Module hierarchy

```
chip            top: external AXI + operation handshake
|-- datapath    operand storage, edge feeding, result streaming
|   `-- array   the PE grid + interconnect          (systolic versions)
|       `-- pe  one processing element (MAC + passthrough registers)
`-- control     FSM: IDLE -> BUSY (compute) -> DONE
```

The `systolic_bram/` datapath additionally instantiates the BRAM banks and replaces the
combinational operand feed with a synchronous-read pipeline (see Design Notes).

---

## Systolic dataflow

For an MxN * NxK product, the array is an M (rows) by K (columns) grid of PEs; each PE
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

Each PE performs one MAC per cycle (`acc += a_in * b_in`) and registers its passthroughs
(`a_in -> a_out` rightward, `b_in -> b_out` downward), so each hop costs one cycle.
PE(i,j) accumulates C[i][j]; the result is read from `ab_out[i][j]`.

Inputs are skewed — A row i enters i cycles late, B column j enters j cycles late — so the
matching terms of each dot product meet at the right PE on the right cycle. The skew is a
physical consequence of the per-hop register delay, not a scheduled signal, which is why
the array scales: communication is nearest-neighbor only. The last (bottom-right) PE
finishes at ~M+N+K cycles.

---

## Building and testing

Requires Icarus Verilog and cocotb.

```
cd systolic_bram      # or sequential/ or systolic_reg/
make
```

Each `make` compiles the RTL and runs the cocotb regression: 100 trials of random
matrices with randomized backpressure on the output stream, checked against a Python
golden model. The `systolic_bram/` suite includes non-square (M != N != K) cases.

---

## Design notes

**Output-stationary systolic dataflow.** Each PE permanently owns one output element and
accumulates one product per cycle. Operands are skewed (row i of A delayed i cycles,
column j of B delayed j cycles) so the matching terms of each dot product arrive together.
The skew is created physically by each PE registering its passthroughs (one cycle per
hop), so correct global timing emerges from a purely local rule — which is why systolic
arrays scale: communication is nearest-neighbor only, so wire length stays constant as the
array grows.

**Compute latency ~M+N+K.** The last PE finishes at cycle `i + j + (N-1)` for grid
position (i,j), maximized at the bottom-right corner: `(M-1) + (K-1) + (N-1)`. Three
contributions: skew ramp-in, propagation to the far corner, and the N-term accumulation
along the shared dimension.

**Registered AXI master under backpressure.** Output `tdata`/`tvalid`/`tlast` are
registered (clean timing boundary). `tvalid` doubles as a "slot full" flag; the output
register advances only on an accepted transfer (`tvalid && tready`) and otherwise holds,
which makes backpressure correct by construction.

**BRAM banking.** A single BRAM has one read port (one value per cycle), but the systolic
feed needs one value per grid row of A and per grid column of B each cycle. So storage is
split into independently addressed banks — A by row, B by column — read in parallel. The
access pattern dictates the banking.

**Synchronous-read latency.** BRAM returns data one cycle after the address is presented.
The operand feed is therefore pipelined: present each bank's address per the skew
schedule, carry a registered "valid" flag so it lines up with the late-arriving data, and
mask out-of-window reads to zero. The whole compute timeline shifts one cycle later than
the register version (reflected in the drain threshold).

**Generalizing to MxN * NxK.** The PE is unchanged; only dimensions are parameterized.
The grid becomes M rows by K columns; each PE accumulates N terms. The feed active-window
length is the shared dimension N (not the grid size); the output stream stride is K (the
output row length); and A and B are banked by row and column respectively over their own
inner dimensions. The square case M = N = K reduces to the original NxN design, which the
test suite retains as a regression.

---

## Verification

- Python golden model (`golden_model.py`) — reference triple-nested matrix multiply.
- 100 randomized trials per run: random matrices + random per-cycle backpressure on the
  output stream; `systolic_bram/` includes non-square cases.
- Timeouts on all wait loops, so a stalled handshake fails as a located error rather than
  hanging.

---

## Roadmap

- [ ] Explicit edge-case tests: identity (A*I == A), all-max-value (accumulator-width
      stress), all-zeros, single non-zero.
- [ ] Parameter sweep across a range of M, N, K, WIDTH, as separate tests so failures
      localize.
- [ ] FPGA deployment (Vivado -> Zynq), report achieved Fmax and resource utilization.
- [ ] ASIC flow (Genus -> Innovus on a 7nm PDK), RTL-to-GDSII with timing closure.

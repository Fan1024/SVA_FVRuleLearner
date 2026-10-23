# opentitan_spi_device_fifo provenance

assembled: 2026-08-19

source: an upstream opentitan clone (read only; the upstream
tree was not modified)

**This is not a port. There was no source package.** The RTL is upstream
lowRISC OpenTitan, copied byte-identical out of the tree above; the formal top,
the four oracles, the 50 candidate targets, the 37 covers and the whole of
`lists/` were written for this package. The shape follows
`tasks/opentitan_entropy_chain/PROVENANCE.md`, which solved the same
dependency-collection problem for entropy_src/csrng/edn.

## Which IP, and why

`hw/ip/spi_device`. It was the first choice in the brief and it held up: it is
the only OpenTitan block in this tree whose datapath is a genuine
**clock-domain-crossing subsystem** -- the SPI host's SCK on one side, the chip
bus clock on the other, with real asynchronous FIFOs and a dual-port SRAM
between them. `flash_ctrl` and `spi_host` were not needed as fallbacks.

The subsystem is the **command upload path plus its two return paths**, wired
the way `hw/ip/spi_device/rtl/spi_device.sv` wires the same blocks:

    SPI pins -> spi_s2p -> spi_cmdparse -> spid_upload --+--> u_cmdfifo  --\
                                 |                       +--> u_addrfifo --+-> DPSRAM
                                 |                       +--> payload ----/     |
                                 |                                              |
                                 +-> spid_status <- prim_fifo_async <-----------(bus)
                                 +-> spid_jedec                                 |
                                 +-> spi_p2s -> SPI pins        prim_sram_arbiter
                                                                (sw + cmd + addr)

Ten spi_device blocks, two arbiters, two asynchronous FIFO primitives and an
asynchronous dual-port SRAM. That is a subsystem, not a block.

top: `opentitan_spi_device_fifo_ft`
environment: `lists/diag_opentitan_spi_device_fifo.tcl` (task
`diag_opentitan_spi_device_fifo`, **NO assumptions**)
declared target for `cex.tcl`'s census: `T_DATA_CMDFIFO_POP_EQ_PUSH`

## THE CLOCK ASSUMPTION -- read this before reading any target

spi_device is a **two-clock** design. `clk_i` is the chip bus clock; SCK is
driven by the external SPI host and is asynchronous to it in both phase and
frequency. Our flow proves under a **single-clock** formal setup.

**This package drives BOTH domains from `clk_i`.** In
`ft/opentitan_spi_device_fifo_ft.sv`, `clk_spi_in`, `clk_spi_out` and
`clk_sys` are all `clk_i`: a fixed **1:1, edge-aligned** clock ratio.
`lists/tc_elab.tcl` declares `clock clk_i` and nothing else.

Two consequences, and they change what every target below means:

1. **What is still under proof.** The CDC STRUCTURE is entirely intact. The
   gray encode and decode, both 2-flop synchronisers in each async FIFO, the
   stale read pointer the writer computes `w_full` from, the stale write
   pointer the reader computes `rdepth` from, the SRAM read latency and the
   `stored`/`r_sram_rvalid` holding register are all in the design and all
   exercised. `T_DATA_CMDFIFO_POP_EQ_PUSH` is still a statement about a word
   surviving a gray-pointer FIFO whose storage is in a dual-port SRAM shared
   with an unconstrained software port.
2. **What is NOT under proof.** Metastability, and any bug that needs an
   arbitrary phase or a frequency ratio other than 1:1 -- a pointer sampled
   mid-transition, a multi-bit signal crossing without a gray code, a pulse
   narrower than the destination clock period. A proof of any target here is
   **not** a proof that the CDC is correct at an arbitrary ratio. Nothing in
   this package should be reported as CDC verification.

Third, smaller, and also an assumption: **SCK free-runs.** In the real chip SCK
only toggles while CSb is asserted. Here it runs every cycle, and CSb frames a
transaction the way upstream frames it, through the reset
`rst_spi_n = rst_ni & ~csb`. The SPI-domain blocks are held in reset between
transactions, so nothing advances while CSb is high; what differs from silicon
is that the SPI-domain flops see clock edges they would not otherwise see.

Fourth: **CSb is registered into the bus clock domain** before use. Upstream
clocks one flop in `spid_csb_sync` and one in `spid_status` on the POSEDGE of
CSb, which as a free primary input would be a second free-running clock. The
formal top registers CSb (`csb_q`) so those two flops are clocked by a signal
DERIVED from `clk_i`, which `set_clock_reference_mode auto` resolves. The cost
is one cycle of CSb latency and the loss of any bug that needs CSb to move
between bus clock edges.

None of the four is written as an `assume`. They are all in the structure of
the formal top and in `lists/tc_elab.tcl`, which is why they are stated here in
full: a constrained clock relationship must not be silent.

## What was carried over unchanged

`rtl/` -- **53 files, byte-identical upstream OpenTitan.** Verified with `cmp`
against the upstream paths below; **nothing was scrubbed, so there is no
"Scrubbed" section in this file.** 44 are on the analyze list
(`lists/tc_elab.files`, 9,512 lines); the other 9 (`prim_assert.sv`,
`prim_assert_{dummy,standard,yosys}_macros.svh`, `prim_assert_sec_cm.svh`,
`prim_flop_macros.sv`, `prim_macros.svh`, `prim_fifo_assert.svh`,
`prim_util_memload.svh`) are macro files reached by `` `include `` through
`+incdir+rtl`, exactly as the upstream flow reaches them.

Where the set came from: the transitive module and package closure of
`spi_s2p`, `spi_cmdparse`, `spid_upload`, `spid_status`, `spid_jedec`,
`spi_p2s`, `spid_addr_4b`, `spid_csb_sync`, `spid_dpram` and
`prim_sram_arbiter`, computed by walking instantiations and `pkg::` references
over `hw/ip/*/rtl`, `hw/ip_templates/*/rtl` and the three `hw/top_*/rtl` trees.
Slang elaborates the top **without** `--ignore-unknown-modules`, which is the
check that the closure is complete: no module is silently black-boxed.

| group | files | why it is here |
| --- | --- | --- |
| spi_device (`hw/ip/spi_device/rtl`) | 10 | the blocks and the two packages |
| prim async FIFOs (`hw/ip/prim/rtl`) | 2 | `prim_fifo_async`, `prim_fifo_async_sram_adapter` |
| prim SRAM (`hw/ip/prim/rtl`, `hw/ip/prim_generic/rtl`) | 8 | the two `*_async_adv` wrappers, the two generic arrays, four SECDED codecs |
| prim arbiters and FIFOs | 5 | `prim_sram_arbiter`, `prim_arbiter_ppc`, `prim_arbiter_tree`, `prim_fifo_sync`, `prim_fifo_sync_cnt` |
| prim sync / flops / packages | 19 | `prim_flop_2sync`, `prim_pulse_sync`, `prim_sync_reqack(_data)`, `prim_count`, the generic flop cells, five `_pkg` files |
| macro includes | 9 | reached by `` `include ``, not on the list |
| **read but scoped out** | -- | see below |

`prim_buf`, `prim_flop`, `prim_flop_en`, `prim_flop_2sync`, `prim_clock_mux2`,
`prim_ram_1r1w` and `prim_ram_2p` are taken from `hw/ip/prim_generic/rtl`,
which is what the upstream simulation and FPV flows pick up. The `xilinx` and
`asap7` trees carry same-named modules that instantiate vendor cells.

### What is deliberately NOT here

- **`spi_device_reg_top.sv` (22,049 lines) and the whole `hw/ip/tlul` tree.**
  Every block in the subsystem takes plain signals rather than a TL-UL port, so
  tying the CSR side off with a CONSTANT configuration removes the register
  file and its adapter closure without touching the datapath. Same scoping
  decision as `tasks/opentitan_entropy_chain`, which dropped three `_reg_top`s
  the same way.
- **`spi_readcmd`, `spid_readsram`, `spid_readbuffer`** -- the flash read path,
  bus -> SPI through the egress half of the SRAM. Left out to keep the formal
  top's configuration surface small; its absence is why the six read-command
  `cmd_info` slots and the SFDP slot are configured INVALID. The bus -> SPI
  direction is still covered, through `spid_status`'s `prim_fifo_async`.
- **`spi_passthrough`, `spi_tpm`.** Passthrough needs a second SPI port and a
  downstream flash device; TPM is a separate protocol with its own FIFOs and
  would roughly double the package.

## What was written for this package

    ft/opentitan_spi_device_fifo_ft.sv      the formal top: ten blocks wired as
                                            spi_device.sv wires them, a constant
                                            CSR-side configuration, and eleven
                                            free inputs
    sva/targets_opentitan_spi_device_fifo.sv  four shadow oracles, a set of
                                            saturating counters and 50 `T_*`
                                            assertions
    sva/covers_opentitan_spi_device_fifo.sv   37 `C_*` covers, one or more per
                                            category used
    lists/tc_elab.files                     the analyzed file list, package-root-
                                            relative, and the file the round
                                            appends `../submission/<worker>.sv`
                                            lines to. 44 source lines, 104 lines
                                            with its comments; ends with a
                                            newline; no absolute paths
    lists/tc_elab.tcl                       the elaboration recipe
    lists/diag_opentitan_spi_device_fifo.tcl  defines
                                            `setup_diag_opentitan_spi_device_fifo`
                                            and the alias
                                            `setup_opentitan_spi_device_fifo`
    lists/reset_modes.tcl                   `rm_all_registers` + `_rm_apply_reset`.
                                            Reset is ACTIVE LOW here (`rst_ni`)
    lists/targets.txt                       50 rows, `label TAB category TAB intent`
    taskdef.json                            dropped in beside the package rather
                                            than added to `taskdefs.TASKS`

Copied verbatim from `tasks/opentitan_tlul_socket_order/lists/` because both are
task-agnostic: `lists/proofgrid_profiles.tcl` (sourced by our own `tc_elab.tcl`)
and `lists/vendor/iterdev_utils.tcl` (`safe_assume`; our diag declares no
assumptions and does not call it, but `cex.tcl`/`check.tcl` source it when
present).

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on the first
run. It is derived, not authored.

## Where the buffering sits

| buffer | direction | shape | depth |
| --- | --- | --- | --- |
| `u_upload.u_cmdfifo` | SPI -> bus | `prim_fifo_async_sram_adapter`: gray pointers, 2-flop sync each way, storage in the DPSRAM | 16 x 16 bit |
| `u_upload.u_addrfifo` | SPI -> bus | the same | 16 x 32 bit |
| `u_upload.u_payload_buffer` | SPI -> bus | `spid_fifo2sram_adapter`: packs four SPI bytes per SRAM word, circular | 256 byte |
| `u_spid_status.u_sw_status_update_sync` | **bus -> SPI** | `prim_fifo_async`: gray pointers, 2-flop sync each way, own storage | 2 x 24 bit |
| `u_spid_dpram.u_spi2sys_mem` | SPI write, bus read | `prim_ram_1r1w_async_adv`, byte parity | 128 x 32 bit |
| `u_spid_dpram.u_sys2spi_mem` | bus write, SPI read | the same | 1024 x 32 bit |

The two `prim_sram_arbiter` instances are the contention: `u_upload.u_arbiter`
(command FIFO / address FIFO / payload, SPI side) and `u_sys_sram_arbiter`
(**free software port** / command FIFO read / address FIFO read, bus side).
Three independent flows sharing one resource on each side, which is the shape
the target spec asks for.

## The bounded environment, and why there is no assumption

Eleven free inputs and nothing else:

| input | what it is |
| --- | --- |
| `csb_i` | SPI chip select, active low, may move at any time |
| `sd_i[3:0]` | the four SPI data pins into the device |
| `cmdfifo_rready_i`, `addrfifo_rready_i` | software popping the two upload FIFOs |
| `fw_req_i`, `fw_write_i`, `fw_addr_i`, `fw_wdata_i`, `fw_wmask_i` | the software SRAM port, one of three requesters on the bus-side arbiter. **Unconstrained**: it may hammer the arbiter and it may write any address with any data |
| `sys_status_we_i`, `sys_status_i[23:0]` | software writing FLASH_STATUS |

Everything else is a combinational constant:

- **spi mode** is `FlashMode`; `rxorder` and `txorder` are MSB-first.
- **`cmd_info[NumTotalCmdInfo]`** is a constant array. Read Status 1/2/3
  (05h/35h/15h) and Read JEDEC ID (9Fh) are valid; **Read SFDP and the six
  read-data slots are INVALID**, because `spi_readcmd` is not in this package
  and a command selecting it would drive a datapath with nothing behind it.
  Four reserve slots carry the four upload shapes the FSM has to distinguish:
  Page Program 02h (opcode + address + payload), Sector Erase 20h (opcode +
  address), Chip Erase C7h (opcode only), Write Status 01h (opcode + payload).
  EN4B B7h, EX4B E9h, WREN 06h and WRDI 04h fill the four fixed slots.
- **JEDEC configuration** is a constant `{num_cc, cc, jedec_id, device_id}`.
- **scan mode** is `MuBi4False` and `scan_rst_ni` is 1.
- **`sys_update_clr_i`** is 0, so the status sync FIFO is never cleared.
- **`spid_addr_4b`'s CSR side** is tied to 0, so the 3B/4B mode is changed only
  by EN4B/EX4B commands arriving over SPI.

**There is no `assume` in this package and none in the diag.** That is why the
CSR side is a constant rather than a constrained symbolic interface: a constant
is part of the design under proof and shows up in the design map, where an
assumption is a promise the round has to carry. Confirmed by counting the
elaborated properties: 87 concurrent assertions in the whole design, which is
exactly the 50 targets plus the 37 covers, and zero of anything else --
`+define+SYNTHESIS` empties every `` `ASSERT ``/`` `ASSUME `` embedded in the
upstream RTL, including `spid_upload`'s three `CmdFifoNeverFull_M` /
`AddrFifoNeverFull_M` / `PayloadNeverFull_M` assumptions, which would otherwise
assume away exactly the overflow the occupancy targets are about.

## The oracles

Four shadow queues and a set of saturating counters, in
`sva/targets_opentitan_spi_device_fifo.sv`, all independent of the design's own
bookkeeping:

- **A -- the command FIFO shadow.** A 16-deep copy of the 16-bit words the SPI
  domain pushed, with this file's own push and pop counters. The design's copy
  lives in the SRAM and is addressed by gray-coded pointers.
- **B -- the address FIFO shadow.** The same, 32 bits wide.
- **C -- the payload shadow.** This file's own copy of the first 16 payload
  bytes of the current transaction and its own byte index, cleared on the same
  event that clears `spid_fifo2sram_adapter`'s pointer and `spid_dpram`'s
  `initialized_words_q` -- the SPI-domain reset, i.e. CSb de-assertion.
- **D -- the status sync shadow.** A 2-deep copy of the 24-bit FLASH_STATUS
  words software pushed into the bus -> SPI `prim_fifo_async`.
- **C' -- a 4-deep queue of the addresses the bus-side SRAM read pipeline owes
  a response for.** `prim_ram_1r1w_async_adv` is fixed latency, so responses
  come back in issue order.
- **E -- saturating wait counters**, which is how the fairness,
  bounded-response and deadlock obligations are written as safety properties.
  **There is no `s_eventually` in this package**: the reset cut admits states
  not reachable from reset, so a liveness property is either false or vacuous.

### Where the oracle does read a design wire, and why

The PUSH EVENTS, and nothing else. A shadow has to know *when* a word entered
a FIFO, and that is `cmdfifo_wvalid && cmdfifo_wready` (and the two siblings)
at the FIFO's own write port. This is the same shape as
`tasks/l15_l2_mshr_onehot`'s shadow of the L1.5 NOC1 command buffer, which takes
the design's push and pop events and keeps its own pointers, occupancy and
payload copy. The **payload**, the **order**, the **counts** and the
**occupancy** are this file's own arithmetic, and every comparison happens at
the formal top's BOUNDARY -- `cmdfifo_rdata_o` at
`cmdfifo_rvalid_o && cmdfifo_rready_i`.

Six targets deliberately COMPARE a shadow against a named design register or
output: `T_ORDER_CMDFIFO_RPTR_TRACKS_POP_COUNT`,
`T_ORDER_ADDRFIFO_RPTR_TRACKS_POP_COUNT`,
`T_CONSERV_CMDFIFO_WPTR_EQ_PUSH_COUNT`, `T_BOUND_CMDFIFO_RDEPTH_LE_OCC`,
`T_ALLOC_CMDFIFO_WPTR_ONLY_ON_PUSH` and `T_ALLOC_CMDFIFO_WPTR_STEPS_BY_ONE`.
Those rows say so in `lists/targets.txt`; they are the ordering, conservation
and allocator rows, not the data-integrity rows.

### Why the headline target is hard

Between the push and the pop of a command word sit: the gray encode, a 2-flop
synchroniser, the gray decode, the read-side pointer, an SRAM read request
through a round-robin arbiter **shared with an unconstrained software port**,
a 1-cycle SRAM pipeline and the `stored` holding register. Because the software
port may write any address with any data, `T_DATA_CMDFIFO_POP_EQ_PUSH` is also
the statement that software cannot corrupt an uploaded command -- `spid_dpram`
routes bus-side writes to the egress memory only, and the ingress memory the
FIFOs live in has exactly one writer, the SPI domain.

## Assertions per category

| # | category | count |
| --- | --- | --- |
| 1 | end-to-end ordering | 3 |
| 2 | data integrity | 6 |
| 3 | uniqueness / no duplication | 2 |
| 4 | no loss / conservation | 3 |
| 5 | mutual exclusion / one-hot | 4 |
| 6 | occupancy and bounds | 7 |
| 7 | allocator discipline | 3 |
| 8 | request-response correspondence | 4 |
| 9 | protocol conformance | 4 |
| 10 | arbitration fairness | 2 |
| 11 | bounded response | 2 |
| 12 | deadlock freedom | 2 |
| 13 | reset / initialisation | 3 |
| 14 | lifecycle / access control | 4 |
| 15 | coherence | 1 |
| | **total** | **50** |

37 covers, at least one per category used. Occupancy and bounds and data
integrity are the two heaviest, which is where the first phase-1 screen found
hard targets live.

The single coherence row is
`T_COHERE_CMDFIFO_TRUE_PTR_GAP_LE_DEPTH`: the two clock domains hold different
views of one FIFO -- the writer a stale read pointer, the reader a stale write
pointer -- and the gap between the two TRUE pointers must never exceed the
depth, or the two views disagree about who owns a slot.

## DESIGN_KEEP

`taskdef.json` carries one pattern:

    u_targets\.

Under `ENTER_FRA_KEEP` every register no keep pattern matches starts arbitrary.
Every register inside `u_targets` is oracle state: the four shadow queues,
their counters, the read-address queue, the six wait counters and the `started`
guard. An oracle counter that starts arbitrary falsifies its target at cycle 0
for a reason the design cannot correct, and the `started` guard starting
arbitrary at 1 would un-guard nothing but starting arbitrary at 0 would make
every gated target vacuous -- a false PASS. A blanket pattern rather than the
per-register list `tasks/opentitan_entropy_chain` uses: the rule is "preserve
the instrument, cut the design", and everything in `u_targets` is instrument.

Nothing on the design side is kept, and that is the point: the invariants that
relate the gray pointers, the synchronisers, the SRAM and the two arbiters to
the oracle are exactly what a round is asking an agent to write.

## Assertions I am not confident are true

Recorded here and not only in the report, because a number published without its
known caveats is worse than no number. None of these was tuned to pass; the
phase-1 screen is what decides.

**Certain to be falsified under the FRA reset cut, kept because the category
asks for them:**

- `T_RESET_CMDFIFO_EMPTY`, `T_RESET_UPLOAD_FSM_IDLE`,
  `T_RESET_PAYLOAD_PTR_ZERO`. All three read a DESIGN register in the first
  cycle out of reset, and the cut is exactly what makes that register
  arbitrary. True under a concrete reset, false under `fra_keep`. The reset
  category has no encoding that survives the cut, and saying so is the result.

**Likely to be falsified under the cut, for a reason a helper cannot repair:**

- `T_ORDER_CMDFIFO_RPTR_TRACKS_POP_COUNT`,
  `T_ORDER_ADDRFIFO_RPTR_TRACKS_POP_COUNT` and
  `T_CONSERV_CMDFIFO_WPTR_EQ_PUSH_COUNT`. Each equates a design pointer with an
  oracle count; cut, the design pointer starts arbitrary and the equality is
  false at cycle 0 for ever after. These are the rows the screen should
  reclassify, not the data-integrity rows.

**Uncertain for a design reason, not a cut reason:**

- `T_FAIR_SYS_SRAM_FW_WAIT_LE_4` and `T_FAIR_SCK_SRAM_PAYLOAD_WAIT_LE_4`. Both
  read `prim_arbiter_ppc` as strict round-robin over N=3 with `ready_i` tied
  high, so a holding requester is passed over at most twice. That is what the
  module's mask register says, but it was not proved.
- `T_BOUNDRSP_CMDFIFO_VISIBLE_LE_16`. The number is two cycles of pointer
  synchroniser plus at most three of arbiter plus the SRAM latency, rounded up.
  If the read-side request logic has a path I did not trace -- and
  `r_sram_req_o`'s Karnaugh map has four cases -- the counter runs past 16.
- `T_BOUNDRSP_SYS_SRAM_READ_LE_8` and `T_DEADLOCK_{CMD,ADDR}FIFO_DRAIN_LE_32`.
  Same kind of number: local progress bounds read off the pipeline rather than
  proved.
- `T_DATA_PAYLOAD_SYS_READ_EQ_SHADOW`. The most fragile row here. It compares
  the bus-side SRAM read data against the payload shadow, guarded by
  `pl_quiet >= 4` and a twice-delayed valid mask so that the comparison clears
  the write pipeline. The margins were computed by hand from
  `prim_ram_1r1w_async_adv` with both pipeline options off (write lands one
  edge after the request, read data one edge after the request); if the SRAM
  wrapper has a stage I miscounted, the guard is one cycle short and the target
  is false.
- `T_PROTO_CMDFIFO_RVALID_STABLE` and `T_PROTO_CMDFIFO_RDATA_STABLE`. Read off
  `prim_fifo_async_sram_adapter`'s `store_en` Karnaugh map, which does keep
  `stored` set while `rready` is low. Not proved, and the module's own
  `SramRvalid_A` assertion suggests the author was not certain either.
- `T_PROTO_SPI_SRAM_WRITE_IN_INGRESS`. The three SPI-side writers address
  `SramPayloadIdx + 0..63`, `SramCmdFifoIdx + 0..15` and
  `SramAddrFifoIdx + 0..15`, all inside the 112-word ingress window at word
  896. Arithmetic checked by hand, not proved.
- `T_ACCESS_CMDFIFO_OPCODE_IS_CONFIGURED_UPLOAD`. Depends on `spi_cmdparse`
  asserting `DpUpload` only for a slot with `upload` set, and on the byte
  `spid_upload` samples at that moment being the opcode byte. Read, not proved.
- `T_LIFE_BUSY_STICKY_UNTIL_SW_CLEARS`. `sck_status_staged[BitBusy]` has three
  assignment arms; the property covers the two I found. If a fourth path clears
  it the target is false.

**Where the clock assumption is doing the work.** Every CDC target above --
`T_DATA_CMDFIFO_POP_EQ_PUSH` first among them -- is proved at a 1:1
edge-aligned ratio. A cex is real; a proof is a proof about that ratio and not
about the CDC.

## Verified

    uv run python v6_dataset/elab_local.py --task opentitan_spi_device_fifo
    OK: opentitan_spi_device_fifo elaborates

Run with `sva/targets_opentitan_spi_device_fifo.sv` and
`sva/covers_opentitan_spi_device_fifo.sv` ON `lists/tc_elab.files`, not with
`--extra`. Slang, run directly with the same argv, reports
`0 errors, 0 warnings`, and also elaborates **without**
`--ignore-unknown-modules`, which is the check that no module in the closure is
missing. The elaborated AST holds 87 concurrent assertions and no others.

The 50 labels in `sva/targets_opentitan_spi_device_fifo.sv`, the 50 rows of
`lists/targets.txt` and the 50 entries of `taskdef.json`'s `target_labels` are
the same set (`diff` clean). `taskdefs.TASKS` admits the task and
`taskdefs.DESIGN_KEEP` carries the one pattern.

The targets module is **instantiated** (`u_targets`) by the formal top, not
bound, so the gate's instantiation check passes and all 50 assertions are live.
There is no `bind` in this package.

## Not verified

**No Jasper elaboration has been run.** `tc_elab.tcl`,
`diag_opentitan_spi_device_fifo.tcl` and `reset_modes.tcl` are unexecuted.
Slang and Jasper disagree about some SystemVerilog and only Jasper's verdict
admits a package to a round. Three things in particular are untested against
Jasper:

- **`set_clock_reference_mode auto` against the two CSb-derived clocks.**
  `spid_csb_sync.csb_toggle` and `spid_status.u_sck2csb_status` are clocked on
  the posedge of `csb_q`. `csb_q` is registered off `clk_i`, so it is a derived
  clock, but whether Jasper resolves it without an explicit `clock` declaration
  was not tested. If it does not, the fix is a second `clock` line in
  `tc_elab.tcl` -- and that changes the setup enough that the clock section
  above has to be rewritten.
- **The hierarchical references into generate blocks.** Slang collapses
  `spid_dpram`'s `gen_ram1r1w` in its AST dump; Jasper will not. No target
  references inside `spid_dpram`, so this should not bite, but it was not
  checked.
- **`+define+SYNTHESIS`**, which is load-bearing for the property census above.

No proof of any kind has been run, so **no claim is made about which of the 50
assertions is true**. The list above says which ones I expect to fail and why.

## No hashing

No content hash, checksum or hash-based identifier is recorded anywhere in this
package. Identity is the readable name plus this file.

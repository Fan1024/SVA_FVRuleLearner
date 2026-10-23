# corundum_tx_rx_datapath provenance

assembled: 2026-08-19

source: **there is no source package.** This is not a port. The RTL is upstream
Corundum, copied out of a working clone; the formal top, the environment, the
oracle, the candidate targets and everything under `lists/` were written here.

    upstream: github.com/corundum/corundum
    clone:    an upstream corundum clone
    commit:   1ca0151b97af85aa5dd306d74b6bcec65904d2ce  (2023-12-02)

top: `corundum_tx_rx_datapath_ft`
environment: `lists/diag_corundum_tx_rx_datapath.tcl`
(task `diag_corundum_tx_rx_datapath`, **NO assumptions** -- see "The
environment is built, not assumed" below)
candidates: 50 `T_*` assertions and 30 `C_*` covers in
`sva/targets_corundum_tx_rx_datapath.sv`, listed with category and intent in
`lists/targets.txt`.

## Why this cut, and how it differs from `corundum_dma_path`

The corpus already had a Corundum task. `corundum_dma_path` uses **9 files of a
1023-file upstream** and stops at the descriptor: a fetch is turned into work by
an authored stand-in engine, and the "work" is a completion. There is no packet,
no MAC, and no receive side at all.

This package is the deep cut of the same upstream: **28 source files, 12,666
lines, 58 upstream instances**, and it is the whole NIC datapath taken together
--- descriptor fetch, transmit packet path, MAC interface, receive packet path,
completion writeback --- with **seventeen distinct queues between the stages**.
The buffering is the point: a payload byte crosses five separate
store-and-forward or elastic buffers between the host read that produced it and
the host write that delivers it, and nothing local keeps those five in step.

## The chain, and where the queues sit

    env_txreq  (one transmit request at a time: ring, tag, MAC port)
         |  s_axis_tx_req
         v
    == mqnic_interface_tx ============================================
    |  tx_engine, 4-entry descriptor table                            |
    |  QUEUE 1: tx_desc_fifo      axis_fifo, 64 B of 128-bit descrs   |
    |  QUEUE 2: dma_psdpram_tx    256 B transmit packet RAM           |
    |  dma_client_axis_source -> mqnic_egress ->                      |
    |  QUEUE 3: tx_csum_cmd_fifo  axis_fifo, 32                       |
    |  QUEUE 4: tx_checksum's data_fifo (64 B) + csum_fifo (64)       |
    ==================================================================
         |  descriptor request           |  transmit packets, 64-bit,
         v                               |  tid = ring, tdest[4] = MAC port
    == desc_op_mux == (TWO FLOWS:        v
    |  transmit and receive share    == tx_fifo (PORTS = 2) ==========
    |  ONE descriptor fetcher)       |  axis_demux, routed on tdest[4] |
         |                           |  QUEUE 7, 8: two               |
         v                           |  axis_fifo_adapter, FRAME_FIFO |
    == desc_fetch ==============     |  128 B, store-and-forward,     |
    |  QUEUE 5: dma_psdpram     |    |  64 -> 32 bit axis_adapter     |
    |  128 B descriptor RAM     |    =================================
    |  dma_client_axis_source   |         |  32-bit MAC x 2
    ============================         v
         |  dequeue req/resp/commit   env_mac x 2 -- loopback with a bounded
         v                            |  stall and the transmit completion
    == queue_manager x 2 =======      |  the PTP path would return
    |  QUEUE 6: 4-entry op table|     v
    |  transmit ring pair,      | == rx_fifo (PORTS = 2) =============
    |  receive ring pair        | |  QUEUE 9, 10: two axis_fifo_adapter |
    ============================ |  FRAME_FIFO 128 B, 32 -> 64 adapter |
         ^                       |  axis_arb_mux, round robin,         |
         |  AXI-Lite bring-up    |  tid := source MAC port             |
    env_cfg_txq / env_cfg_rxq    ======================================
                                      |  receive packets, 64-bit
                                      v
    == mqnic_interface_rx ============================================
    |  mqnic_ingress: rx_hash + rx_checksum,                          |
    |    QUEUE 11 rx_hash_fifo, QUEUE 12 rx_csum_fifo,                |
    |    QUEUE 13 rx_hash_data_fifo (256 B)                           |
    |  rx_engine -- descriptor request --> desc_op_mux, second flow   |
    |    QUEUE 14: rx_desc_fifo   axis_fifo, 64 B                     |
    |    mqnic_rx_queue_map: MAC port -> receive ring                 |
    |  QUEUE 15: dma_psdpram_rx   256 B receive packet RAM            |
    |  dma_client_axis_sink                                           |
    ==================================================================
         |  DMA write descriptor        |  completion request
         v                              v
    env_host_rxdata  (THE FAR END   == cpl_op_mux == (TWO FLOWS: transmit
    of the packet: publishes every  |  and receive completions share ONE
    64-bit word the receive DMA     |  completion writer)
    hands host memory)                   |
                                         v
                                    == cpl_write =================
                                    |  QUEUE 16: 4-entry table    |
                                    |  + 32 B completion data RAM |
                                    ==============================
                                         |  enqueue req/resp/commit
                                         v
                                    == cpl_queue_manager =========
                                    |  QUEUE 17: 4-entry op table |
                                    |  2 completion rings, phase  |
                                    ==============================
                                         |  DMA write descriptor
                                         v
                                    env_host_cpl  (THE FAR END of the
                                    descriptor: the 256-bit completion word)

Five distinct upstream blocks with real queue buffering between them, which is
more than the "at least three" the scope rule asks for: the descriptor
machinery (`desc_fetch`, `desc_op_mux`, two `queue_manager`s), the transmit
interface (`mqnic_interface_tx`, `tx_engine`, `mqnic_egress`, `tx_checksum`),
the MAC-side frame buffers (`tx_fifo`, `rx_fifo` and the AXI-Stream library
under them), the receive interface (`mqnic_interface_rx`, `rx_engine`,
`mqnic_ingress`, `rx_hash`, `rx_checksum`, `mqnic_rx_queue_map`), and the
completion machinery (`cpl_op_mux`, `cpl_write`, `cpl_queue_manager`).

**Two flows share two contended resources.** The transmit and the receive path
both request descriptors through one `desc_op_mux` into one `desc_fetch`, and
both enqueue completions through one `cpl_op_mux` into one `cpl_write`. That is
the "N independent flows sharing one contended resource" shape
`CATEGORIES.md` asks for, twice, and it is what the fairness candidates are
about.

### Geometry

| knob | value | why |
| --- | --- | --- |
| `PORTS` (MAC ports) | 2 | **not 1 -- 1 does not elaborate.** See "Vacuity" below |
| `AXIS_DATA_WIDTH` | 64 | interface-side packet width, 8 bytes per beat |
| MAC width | 32 | **not 64**: a different width on the MAC side puts a real `axis_adapter` in each frame buffer, so the payload is repacked twice on the way round |
| `DESC_SIZE` / `LOG_BLOCK_SIZE` | 16 / 0 | one 16-byte descriptor per dequeue, one 128-bit AXI-Stream beat |
| `CPL_SIZE` | 32 | forced: `tx_engine` writes `m_axis_cpl_req_data[176:168]`, so a completion must be at least 23 bytes, and the field must be a power of two |
| ring geometry | 2 transmit rings, 2 receive rings, 2 completion rings, 4 entries each | two flows per manager, and a ring that wraps inside a reachable trace |
| `MAX_TX_SIZE` / `MAX_RX_SIZE` | 64 bytes | a packet is 8 or 16 bytes, so a frame buffer holds ~8 of them and the receive RAM holds exactly `RX_DESC_TABLE_SIZE` buffers |
| packet length | 8 or 16 bytes, chosen by bit 4 of the descriptor's own host address | two beats or one, so the "consecutive beats step by 8" candidates are not vacuous |
| `MAC_FIFO_DEPTH` | 128 bytes per port | ~8 packets: deep enough that a stalled receive path backs up, shallow enough that overflow is reachable |
| all four table sizes | 4 | `desc_fetch`, `tx_engine`, `rx_engine`, `cpl_write` and both operation tables |
| `PTP_TS_ENABLE` | 0 | the timestamp is 96 bits of datapath no candidate reads. The transmit **completion** handshake is NOT disabled by this and is still load-bearing -- see below |
| `TX_CHECKSUM_ENABLE`, `RX_HASH_ENABLE`, `RX_CHECKSUM_ENABLE` | 1 | **not the cheap setting.** They add six of the twelve `axis_fifo` instances; see "Vacuity" |
| `RAM_PIPELINE` | 2 | `dma_psdpram`'s default; the read path is two registers deep |
| descriptor control word | 0 | so `tx_checksum` is told not to insert, and the payload crosses it unmodified. A non-zero control word would overwrite two payload bytes and the data candidates would be checking the checksum, not the datapath |

### One decision that is not obvious: the transmit completion

`tx_engine` will not start a completion enqueue until `desc_table_tx_done_a`
differs from `desc_table_tx_done_b`, and the only thing that toggles those is

    if (s_axis_tx_cpl_valid && s_axis_tx_cpl_tag[TX_TAG_WIDTH-1])

which in the real design is the port's PTP timestamp return path. So a MAC that
only swallows frames deadlocks the transmit half of the chain. Each
`mqnic_mac_loopback` therefore samples `tuser[TX_TAG_WIDTH:1]` at the frame's
last beat and hands the tag straight back, and `mqnic_txcpl_merge` round-robins
the two ports onto the engine's single completion port. That tag has crossed a
store-and-forward frame buffer and a 64-to-32 width adapter by then, which is
what `T_ALLOC_TXCPL_TAG_MARKED` is about.

## What was carried over unchanged

Byte-identical to the clone, verified by `cmp`, for **26 of the 28 files**. Two
were scrubbed; see below.

    fpga/lib/axis/rtl/                            lines
    rtl/corundum/priority_encoder.v                  92
    rtl/corundum/arbiter.v                          159
    rtl/corundum/axis_fifo.v                        562
    rtl/corundum/axis_adapter.v                     325
    rtl/corundum/axis_fifo_adapter.v                361
    rtl/corundum/axis_demux.v                       301
    rtl/corundum/axis_arb_mux.v                     310

    fpga/lib/pcie/rtl/
    rtl/corundum/dma_psdpram.v                      165
    rtl/corundum/dma_client_axis_source.v           568
    rtl/corundum/dma_client_axis_sink.v             635

    fpga/common/rtl/
    rtl/corundum/queue_manager.v                    686
    rtl/corundum/cpl_queue_manager.v                718
    rtl/corundum/desc_op_mux.v                      435
    rtl/corundum/desc_fetch.v                       651
    rtl/corundum/cpl_op_mux.v                       286
    rtl/corundum/cpl_write.v                        480
    rtl/corundum/tx_checksum.v                      546
    rtl/corundum/mqnic_egress.v                     190
    rtl/corundum/tx_engine.v                       1072
    rtl/corundum/mqnic_interface_tx.v               589   (scrubbed)
    rtl/corundum/tx_fifo.v                          232
    rtl/corundum/rx_checksum.v                      164
    rtl/corundum/rx_hash.v                          330
    rtl/corundum/mqnic_ingress.v                    314
    rtl/corundum/mqnic_rx_queue_map.v               399
    rtl/corundum/rx_engine.v                       1166
    rtl/corundum/mqnic_interface_rx.v               699   (scrubbed)
    rtl/corundum/rx_fifo.v                          231
                                             ------------
                                             28 files, 12,666 lines

**58 upstream instances**, counting everything nested: 12 `axis_fifo`, 8
`priority_encoder`, 4 `axis_adapter`, 4 `axis_fifo_adapter`, 3 `arbiter`, 3
`dma_psdpram`, 2 `dma_client_axis_source`, 2 `queue_manager`, and one each of
`axis_demux`, `axis_arb_mux`, `dma_client_axis_sink`, `desc_op_mux`,
`desc_fetch`, `cpl_op_mux`, `cpl_write`, `cpl_queue_manager`,
`mqnic_interface_tx`, `tx_engine`, `mqnic_egress`, `tx_checksum`, `tx_fifo`,
`mqnic_interface_rx`, `rx_engine`, `mqnic_ingress`, `rx_hash`, `rx_checksum`,
`mqnic_rx_queue_map`, `rx_fifo`. Every one of the 28 files is reached; the list
was read out of the elaborated instance tree, not assumed.

### Which copy, where the clone has more than one

`fpga/lib/axis` is a symlink to `fpga/lib/eth/lib/axis`, so those two paths are
the same file. Three module names exist twice on paths this package could have
used, and only one copy of each may be analyzed:

- `priority_encoder.v` -- taken from `fpga/lib/pcie/rtl/`; `diff` against the
  axis copy is empty.
- `arbiter.v` -- taken from `fpga/lib/axis/rtl/`. The pcie copy differs by five
  lines and is functionally the same module: it puts the register update in the
  reset `else` branch where the axis copy updates unconditionally and lets the
  reset assignment win. The axis copy is the one `axis_arb_mux` sits next to.
- `axis_arb_mux.v` -- taken from `fpga/lib/axis/rtl/`, which is the copy with
  the `UPDATE_TID` parameter that `rx_fifo` sets. The pcie copy is a different
  vintage.

## Scrubbed

Two upstream files carry one line each that Slang 11.0 rejects and Verific
accepts. In both, a `parameter` declared in the **module body** is used in the
**port list**:

    mqnic_interface_tx.v:87   output wire [DMA_CLIENT_LEN_WIDTH-1:0] m_axis_tx_req_status_len,
    mqnic_interface_tx.v:188  input  wire [DMA_CLIENT_LEN_WIDTH-1:0] mtu
    mqnic_interface_rx.v:215  input  wire [DMA_CLIENT_LEN_WIDTH-1:0] mtu

    error: identifier 'DMA_CLIENT_LEN_WIDTH' used before its declaration

The scrub moves that one parameter from the body into the parameter port list,
where the ports can see it. Nothing else changed, and the value is identical:

    mqnic_interface_tx.v
      -   parameter AXIS_TX_USER_WIDTH = TX_TAG_WIDTH + 1
      +   parameter AXIS_TX_USER_WIDTH = TX_TAG_WIDTH + 1,
      +   parameter DMA_CLIENT_LEN_WIDTH = DMA_LEN_WIDTH
      - parameter DMA_CLIENT_LEN_WIDTH = DMA_LEN_WIDTH;     (deleted, line 192)

    mqnic_interface_rx.v
      -   parameter AXIS_RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1
      +   parameter AXIS_RX_USER_WIDTH = (PTP_TS_ENABLE ? PTP_TS_WIDTH : 0) + 1,
      +   parameter DMA_CLIENT_LEN_WIDTH = DMA_LEN_WIDTH
      - parameter DMA_CLIENT_LEN_WIDTH = DMA_LEN_WIDTH;     (deleted, line 219)

The side effect is that `DMA_CLIENT_LEN_WIDTH` becomes overridable from the
instantiation. The formal top does not override it, so the elaborated value is
`DMA_LEN_WIDTH` exactly as upstream computes it. The sibling body parameters
(`DMA_CLIENT_TAG_WIDTH`, and `REQ_TAG_WIDTH` on the receive side) are not used
in either port list and were left where they are.

Slang has `--allow-use-before-declare`, and it was rejected as the fix: the one
place to put it would be `lists/tc_elab.files`, which Jasper reads as an
`analyze -f` list and would treat as a filename.

## Vacuity: what a cheaper parameterisation would compile out

Checked by re-elaborating variants of the formal top and counting instances,
not by reading the generate blocks.

**`PORTS = 1` does not elaborate at all.**

    rtl/corundum/mqnic_rx_queue_map.v:259: error: value must be positive
        indir_tbl_index_reg[INDIR_TBL_ADDR_WIDTH +: CL_PORTS] <= req_id;

At one MAC port `CL_PORTS = $clog2(1) = 0` and the port field of the receive
queue map's index becomes a zero-width part select. So two MAC ports is the
FLOOR of this cut, not a choice --- and at one port `tx_fifo`'s `axis_demux`,
`rx_fifo`'s `axis_arb_mux` and its `arbiter` all sit inside a disabled
`generate`, every per-port ordering candidate is about a wire, and
`T_ORDER_PKT_PORT0_FIFO` is vacuously true.

**The offloads are worth six queues.** With `TX_CHECKSUM_ENABLE`,
`RX_HASH_ENABLE` and `RX_CHECKSUM_ENABLE` all zero the design elaborates but
shrinks from **71 instances to 62**: `tx_checksum`, `rx_hash` and `rx_checksum`
vanish entirely and `axis_fifo` drops from **12 instances to 6**. Every
data-integrity and ordering candidate from the transmit interface onwards would
then be crossing half as many buffers.

**Assertion census in the elaborated AST.** Upstream Corundum is Verilog 2001
and carries no SVA at all --- the only `assert` anywhere in the 28 files is the
word inside a comment in `arbiter.v`. Counted on the elaborated design:

    ConcurrentAssertion: 80   =  50 Assert  +  30 CoverProperty
    Assume: 0    Restrict: 0

50 asserts and 30 covers is exactly this package's own `T_*` and `C_*`, so
nothing upstream can assume away what a candidate tests. This is the check that
caught a `NeverFull` assumption in another package; here it comes back clean.

## What was written for this package

### `ft/corundum_tx_rx_datapath_ft.sv` -- the formal top and the environment

2,543 lines with comments. Nine authored modules:

- **`corundum_tx_rx_datapath_ft`** wires the chain and holds the ring credit
  accounting (`ftenv_tx_credit`, `ftenv_rx_credit`, `ftenv_cq_live`).
- **`mqnic_axil_qcfg`** (x3, one per ring manager) is the driver. Eight
  AXI-Lite writes per ring bring it up --- disable, base low, base high, size,
  linked index, producer pointer, consumer pointer, enable --- and after that
  it sits in RUN and bumps one pointer by one whenever the environment asks and
  its own credit account allows: the producer pointer on a descriptor ring
  (software posting a descriptor), the consumer pointer on a completion ring
  (software retiring a completion). The shadow pointer is the module's own; it
  never reads one back. Adapted from `tasks/corundum_dma_path`, with one
  change: step 4 writes `{8'hC0, LINK_INDEX}` rather than `LINK_INDEX + queue`,
  because here every transmit ring links to completion ring 0 and every receive
  ring to completion ring 1.
- **`mqnic_rss_cfg`** writes the receive indirection table. With `app_mask` and
  `hash_mask` at their reset value of zero, `mqnic_rx_queue_map` indexes the
  table with `{tid, 0}` --- entries 0 and 2 --- so two AXI-Lite writes are the
  whole of the receive steering configuration: MAC port 0 to receive ring 0,
  port 1 to ring 1. The register-block `ctrl_reg` interface is tied off.
- **`mqnic_tx_req_gen`** offers one transmit request at a time and holds ring,
  tag and destination stable until the engine takes it. It only offers a
  request for a ring the driver has actually posted a descriptor to.
- **`mqnic_desc_host_rd`** is host memory on the descriptor side. A descriptor
  is a **pure function of the host address it is fetched from**: bit 17 says
  which ring family, a transmit descriptor asks for 8 or 16 payload bytes
  (alternating with bit 4 of its own address) from `0x4000_0000 | a[15:0]<<8`,
  a receive descriptor offers 64 bytes at `0x8000_0000 | a[15:0]<<8`, and the
  control word is zero.
- **`mqnic_data_host_rd`** is host memory on the transmit packet side. It
  writes `host_word(a) = {a[31:0], ~a[31:0]}` for every 8-byte word the DMA
  read descriptor names.
- **`mqnic_host_wr`** (x2) is host memory on the write side: the receive packet
  data (8-byte words, the far end of the packet) and the completion writeback
  (32-byte words, the far end of the descriptor). Each waits a free 0..3 cycles
  before returning status.
- **`mqnic_mac_loopback`** (x2) is one MAC port: a wire with a stall bounded at
  three consecutive cycles, and the transmit completion return path.
- **`mqnic_txcpl_merge`** round-robins the two ports' completions onto the
  transmit engine's single completion port.

Free top-level inputs: `env_tx_go`, `env_tx_queue`, `env_tx_port`,
`env_tx_tag[2:0]`, four two-bit host turnaround delays, `env_mac_stall[1:0]`,
and six ring-pointer advance controls.

### `sva/targets_corundum_tx_rx_datapath.sv` -- the oracle and the candidates

1,057 lines, bound into the formal top. **The oracle's one idea is that host
memory is a pure function of its own address.**

    host_word(a) = { a[31:0], ~a[31:0] }

A 64-bit packet word therefore carries its own address AND that address's
complement, so it can be checked at any observation point with one register and
no shadow copy of the packet. That is the lesson from
`verilog_ethernet_mac_datapath` applied to a payload: `w[63:32] == ~w[31:0]` at
the far end is an end-to-end data-integrity statement about bytes that have
crossed the transmit packet RAM, the checksum data FIFO, a transmit frame
buffer, a 64-to-32 adapter, the MAC, a 32-to-64 adapter, a receive frame
buffer, the arbiter, the hash data FIFO and the receive packet RAM. A 32-bit
MAC beat gets the same treatment: the odd beat must be the complement of the
even one.

The six things the checker holds, none of them a restatement of the design:

1. `host_word()` and `desc_word()`, recomputed here from addresses seen on the
   DMA wires. The checker never reads a RAM.
2. six shadow FIFOs: the dequeue requests offered to each ring manager, the
   host addresses of started descriptor fetches, the transmit and receive
   packet buffers a descriptor named, and the packets in flight from the
   transmit interface to the receive interface, per MAC port.
3. tag-keyed outstanding sets for the four DMA channels and the two queue
   managers' operation tags.
4. a per-completion-ring slot counter. The k-th completion of ring c must be
   written to entry `k mod 4` of ring c; the checker counts from the address it
   saw on the wire and never reads the manager's producer pointer.
5. frame counters at eleven boundaries, all saturating.
6. eleven saturating wait timers. There is no `s_eventually`, no `F` and no
   `G F` anywhere in this package.

50 `T_<CATEGORY>_<NAME>` assertions across **14 of the 15 categories**, and 30
`C_*` covers with at least one per category used.

**Category 15, coherence, is not used, and that is a result rather than an
omission.** There is no second agent holding a permission on a line anywhere in
this subsystem: the two ring managers own disjoint ring sets, the two MAC ports
own disjoint frame buffers, and the two DMA read channels do not share a
target. The nearest thing to a coherence obligation is
`T_ALLOC_TXQM_OPSET_SUBSET_OF_DESIGN`, filed under allocator discipline.

### `lists/` -- entirely new

    lists/tc_elab.files            the one analyzed, appendable list: 30
                                   source lines (28 upstream, the formal top,
                                   the targets), ends with a newline, no
                                   absolute paths.
    lists/tc_elab.tcl              the elaboration recipe. Corundum ships
                                   cocotb testbenches, not a Jasper flow, so
                                   there is no upstream `tcl/setup.tcl` to
                                   derive it from; it follows the shape of the
                                   other Corundum package and adds only the
                                   clock name (`clk`) and the reset
                                   (`rst == 1'b1`, ACTIVE HIGH).
    lists/diag_corundum_tx_rx_datapath.tcl
                                   defines `setup_diag_corundum_tx_rx_datapath`
                                   at global scope -- `setup_` plus the `diag`
                                   key in `taskdef.json`, which is what the
                                   flow calls -- declares no assumptions, and
                                   prints the assumption, target and cover
                                   census.
    lists/reset_modes.tcl          `rm_all_registers` + `_rm_apply_reset`,
                                   which is all `v5/cex.tcl` calls, on
                                   `rst == 1'b1`.
    lists/targets.txt              one `label<TAB>category<TAB>intent` line per
                                   candidate, checked to match the SVA labels
                                   exactly and in the same order.
    lists/proofgrid_profiles.tcl   copied verbatim from
    lists/vendor/iterdev_utils.tcl `tasks/corundum_dma_path/lists/`; both are
                                   task-agnostic.

`lists/tc_elab.files.slang` is generated by `taskdefs.slang_args` on the first
run. It is derived, not authored, and is gitignored.

## The environment is built, not assumed

`lists/diag_corundum_tx_rx_datapath.tcl` declares **no assumptions**, and
neither does any file in the package. Everything a constraint would normally
say is synthesisable logic in the formal top instead:

- `mqnic_tx_req_gen` holds one request at a time with a stable payload, so no
  AXI-Stream source-stability assumption is needed;
- the three `mqnic_axil_qcfg` instances and `mqnic_rss_cfg` bring every ring
  and the receive steering table up before the first request is offered
  (`all_configured` gates the generator, `desc_fetch.enable` and
  `cpl_write.enable`), so no assumption about queue configuration is needed;
- those drivers are the only writers of a producer or consumer pointer and each
  bumps one by one only while its own credit account allows, so no assumption
  keeps them from over-filling or over-draining a ring;
- all four host-memory responders answer within a bounded number of cycles and
  each `mqnic_mac_loopback` cannot stall its link for more than three
  consecutive cycles, so the fairness, bounded-response and deadlock candidates
  have a real bound rather than an assumed one. This is load-bearing: with an
  unbounded link stall every one of those six candidates is false.

The consequence for a reader of a result is that these numbers are obtained
under a *built* environment, and a built environment is inside the reset cut's
scope. That is what `design_keep` is for.

## `design_keep`, and why each entry is there

    "corundum_txrx_targets\\."    the oracle's own state
    "\\.env_[a-z0-9_]+\\."        the environment submodules' own state
    "ftenv_"                      the environment state in the formal top

`v5/cex.tcl:ENTER_FRA_KEEP` cuts **every** register that no keep pattern
matches. The rule is: preserve the instrument, cut the design.

1. **`corundum_txrx_targets\.`** -- the bound checker. Every one of the 50
   candidates reads it: the six shadow FIFOs, the tag sets, the eleven frame
   counters and the eleven timers ARE the oracle. Cut, they start arbitrary and
   the targets are falsified at cycle 0 for a reason nothing in the design can
   correct. (`taskdefs.oracle_keep` derives this same pattern from the `bind`
   statement; it is written out here so a reader of the file can see it.)
2. **`\.env_[a-z0-9_]+\.`** -- `env_cfg_txq`, `env_cfg_rxq`, `env_cfg_cq`,
   `env_cfg_ind`, `env_txreq`, `env_host_desc`, `env_host_txdata`,
   `env_host_rxdata`, `env_host_cpl`, `env_txcpl` and both `env_mac`. Cut, the
   drivers' shadow pointers and init state start arbitrary, so a ring can be
   posted into before it was configured; the descriptor host can start
   mid-transfer with a latched address it never received and write a descriptor
   the checker cannot predict; and each MAC's three-cycle stall counter starts
   anywhere in 0..3, which changes the worst-case latency every hand-chosen
   bound was computed from. All of that falsifies candidates through the
   *environment*, which no design-side helper can reach.
3. **`ftenv_`** -- the three ring credit accounts. Cut, they start arbitrary and
   the driver over-posts or over-drains a ring, which is an environment reason
   for a conservation candidate to fail.

Everything else is cut: all 28 upstream modules, all 58 instances, the three
packet/descriptor RAMs, the twelve `axis_fifo`s and both frame-buffer pairs,
the four width adapters, the demux and the arbiter, all four operation tables
and both queue RAMs. That is where the difficulty is, and it is the point --
proving that the word the receive DMA hands host memory still carries its own
address needs an inductive invariant spanning `desc_fetch`'s table, the
descriptor RAM, `tx_engine`'s buffer pointer, the transmit packet RAM,
`tx_checksum`'s data FIFO, a frame buffer's commit pointer, an `axis_adapter`'s
partial-word register, the arbiter's grant lock, `mqnic_ingress`'s sideband
handshake and `rx_engine`'s buffer pointer, none of which any target mentions.

All three patterns match at least one register, so none can trip `cex.tcl`'s
"design keep pattern matched nothing" FAIL.

## The gate

    uv run python v6_dataset/elab_local.py --task corundum_tx_rx_datapath
    OK: corundum_tx_rx_datapath elaborates                  (exit 0)

    uv run python -c "import taskdefs; print('corundum_tx_rx_datapath' in taskdefs.TASKS)"
    True

Slang 11.0 reports **0 errors** over the whole package. The 35 warnings are all
in upstream files: 32 `unconnected-{input,output}-port` on the `pause_req` /
`pause_ack` / `status_depth` ports that Corundum's own wrappers leave open on
their `axis_fifo` instances, and 3 `shift-count-overflow` in `rx_checksum`
(`{KEEP_WIDTH{1'b1}} << START_OFFSET` with `KEEP_WIDTH = 8` and
`START_OFFSET = 14`, so the receive checksum mask is all zeros at this data
width and the reported checksum is always 0 --- harmless here, because no
candidate reads it, but it is a real degeneracy of an 8-byte-wide
`rx_checksum` and it is recorded so the next reader does not re-derive it).

## Not verified

**Nothing here has been simulated or elaborated in Jasper.** No simulator is
installed on this machine and no cluster job was launched. What has been
checked is Slang elaboration, the elaborated instance tree, the elaborated
assertion census, and a desk check of the parameter constraints the upstream
modules assert at run time in `initial` blocks --- which no elaborator
evaluates, so they were read and satisfied by hand:

- `desc_fetch`: `DMA_TAG_WIDTH(4) >= CL_DESC_TABLE_SIZE(2)`,
  `QUEUE_REQ_TAG_WIDTH(4) >= CL_DESC_TABLE_SIZE` and `>= REQ_TAG_WIDTH(4)`,
  `AXIS_KEEP_WIDTH*8 == AXIS_DATA_WIDTH` (16*8 = 128), `DESC_SIZE(16)` a power
  of two;
- `cpl_write`: `DMA_TAG_WIDTH(4) >= CL_DESC_TABLE_SIZE+1(3)`,
  `SEG_ADDR_WIDTH(3) >= CL_DESC_TABLE_SIZE(2)`,
  `SEG_COUNT*SEG_DATA_WIDTH(256) >= CPL_SIZE*8(256)`;
- `tx_engine`: `DMA_TAG_WIDTH(4)` and `DMA_CLIENT_TAG_WIDTH(2) >= 2`,
  `DESC_REQ_TAG_WIDTH(3) >= REQ_TAG_WIDTH(3)`, `CPL_REQ_TAG_WIDTH(3) >= 2`,
  `RAM_ADDR_WIDTH(8) >= CL_TX_BUFFER_SIZE(8)`, `TX_TAG_WIDTH(3) >= 3`;
- `rx_engine`: the same four, with `DESC_REQ_TAG_WIDTH(3) >= 2`;
- both `queue_manager`s: `OP_TAG_WIDTH(2) >= CL_OP_TABLE_SIZE(2)`,
  `AXIL_DATA_WIDTH == 32`, `AXIL_ADDR_WIDTH(6) >= QUEUE_INDEX_WIDTH+5`,
  `DESC_SIZE` a power of two, `PIPELINE(2) >= 2`;
- `cpl_queue_manager`: the same, with `AXIL_ADDR_WIDTH(5) >= CQN_WIDTH+4` and
  `CPL_SIZE(32)` a power of two;
- `mqnic_rx_queue_map`: `REG_ADDR_WIDTH(7) >= $clog2(16+PORTS*16) = 6`,
  `AXIL_ADDR_WIDTH(4) >= CL_PORTS+INDIR_TBL_ADDR_WIDTH+2`, and **`RB_NEXT_PTR`
  must not fall inside `[RB_BASE_ADDR, RB_BASE_ADDR+16+PORTS*16)`** --- it is
  64, and the default of 0 would have fired that check;
- `tx_checksum` / `rx_checksum` / `rx_hash`: `KEEP_WIDTH*8 == DATA_WIDTH`;
- `dma_psdpram` x3 and `dma_client_axis_source` x2 / `dma_client_axis_sink`:
  segment widths, `RAM_ADDR_WIDTH == SEG_ADDR_WIDTH + clog2(SEG_COUNT) +
  clog2(SEG_BE_WIDTH)`, and `AXIS_DATA_WIDTH * 2**clog2(PART_COUNT) ==
  SEG_COUNT*SEG_DATA_WIDTH` with `PART_COUNT = 1` on every instance.

The behavioural facts the oracle depends on were read out of the RTL, not
guessed, and are recorded so the next reader does not re-derive them:

- a transmit descriptor is `{addr[127:64], len[63:32], ctrl[31:0]}` and
  `ctrl[31]` is the checksum enable; a receive descriptor uses the same two
  upper fields for its buffer;
- a transmit completion is
  `{.., dest[176:168], .., len[47:32], queue_ptr[31:16], queue[15:0]}` and a
  receive completion the same with `id` in place of `dest`; `cpl_write` returns
  the ring's phase bit as bit `CPL_SIZE*8-1` of the word it DMA-writes;
- `desc_fetch` issues the host read at `desc_table_start_ptr` order and the
  RAM-to-stream read at `desc_table_desc_read_start_ptr` order, both in table
  order, so a FIFO shadow of started fetches is the right oracle;
- `cpl_write` forms the completion DMA write from the enqueue response and
  suppresses it on `full` or `error`, so the per-ring slot counter stays in
  step with the manager's producer pointer;
- `tx_fifo` has `DROP_BAD_FRAME(USER_ENABLE)` with `USER_BAD_FRAME_MASK(1'b1)`,
  so a frame reaching a MAC port has `tuser[0] == 0` by construction;
- `axis_fifo.status_depth` is `{depth_reg, $clog2(KEEP_WIDTH)'b0}` --- BYTES,
  not words --- so the frame-buffer occupancy bound is 128 and not 16.

## What is expected to be wrong

Recorded here BEFORE any proof run, because a number published without its
known caveats is worse than no number.

- **The six hand-chosen bounds** --- `N_BLOCK(200)`, `N_FETCH(400)`,
  `N_PKT(1500)`, `N_PROGRESS(400)`, `N_DFFULL(400)` and the dropped
  `N_TXCPL(64)`. They are estimates from counting handshakes along the chain,
  not measurements. **`T_BOUNDRSP_PKT_TO_HOST_WITHIN_N` is the shakiest of the
  six**: one packet's round trip is a descriptor fetch (a dequeue with a
  two-stage queue-RAM pipeline, a host read, a RAM-to-stream read, a FIFO), a
  packet DMA read, a store-and-forward frame buffer, a MAC with up to three
  stall cycles per beat, a second store-and-forward buffer, the ingress
  sideband handshake, a SECOND descriptor fetch on the receive ring and a
  receive DMA write. 1500 is a guess with maybe a factor of two of margin. If
  one of these comes back `cex`, the right correction is a larger constant, not
  a different property.
- **`T_LIFECYCLE_NO_DEQ_ERROR_AFTER_CONFIG` and
  `T_LIFECYCLE_NO_ENQ_ERROR_AFTER_CONFIG` are expected to be TRUE at real reset
  and FALSE under the cut**, because `configured` is an environment signal and
  the ring-enable bit lives in a design RAM the cut makes arbitrary. They are
  here because the category exists.
- **`T_RESET_DF_TABLE_IDLE`** is an assertion about design registers in the
  first cycle out of reset, and the reset cut starts those registers arbitrary.
  Under FRA it is falsified for a reason nothing can correct. `CATEGORIES.md`'s
  own measured screen found 0 of 4 reset candidates hard; expect this one to
  prove at real reset and be dropped.
- **`T_ORDER_PKT_PORT0_FIFO` and `T_ORDER_RXHOST_MATCHES_RXSTREAM` rest on an
  argument, not a construction.** The first assumes the two frame buffers on
  one MAC port cannot reorder within a port, which is true of a FIFO but is
  being asserted across a demux, an adapter, a MAC and a second adapter. The
  second assumes `rx_engine` issues its receive-DMA writes in the order packets
  arrived; that is how the descriptor table is walked, but the receive path
  also fetches a descriptor per packet through a SHARED arbiter, and if two
  packets' descriptor fetches complete out of order the DMA writes could too.
  If that happens this returns `cex` and the finding is real.
- **`T_DATA_CPL_ADDR_IS_NEXT_RING_SLOT`** predicts the completion ring slot
  from the checker's own count. It is exact only while every enqueue response
  is neither `full` nor `error`; a `full` response produces no DMA write and no
  count, which is handled, but a ring that wraps past its consumer pointer
  while the driver is not retiring will start reporting `full` and the
  interleaving between the two rings has never been exercised.
- **`T_CONSERV_CPL_HOST_LE_CPL_DMA` and the other three conservation
  candidates** are stated over saturating 12-bit counters. Saturation preserves
  `<=`, but a trace long enough to saturate both sides makes them vacuously
  true rather than false; no trace the screen can reach is that long.
- **`T_PROTO_MAC_TUSER_GOOD_FRAME`** assumes the transmit frame buffer never
  emits a partially-drained frame. `FRAME_FIFO(1)` is store-and-forward and
  should make that impossible, but the 64-to-32 adapter sits *after* the FIFO
  and this desk check did not trace its `tuser` handling on a dropped frame.
- **Cover depth is the standing risk for this package, and it is deferred, not
  solved.** Before the first packet can move, three `mqnic_axil_qcfg` instances
  must each complete 8 AXI-Lite writes per ring (16, 16 and 16 writes, in
  parallel, roughly 4 cycles each) and `mqnic_rss_cfg` two more; then one
  packet's round trip is the 1500-cycle estimate above. `C_RXHOST_PACKET_-
  DELIVERED` and everything downstream of it are DEEP covers, and
  `C_RXHOST_TWO_PACKETS` and `C_CPL_BOTH_RINGS` deeper still. The mitigation in
  the file is graduated: `C_CONFIGURED`, `C_TXREQ_ACCEPTED`,
  `C_DESC_FETCH_STARTED`, `C_DESC_STREAM_TX`, `C_TXDATA_DMA_READ`,
  `C_IFTX_FIRST_BEAT`, `C_MAC0_FRAME`, `C_IFRX_FIRST_BEAT`,
  `C_RXDATA_DMA_WRITE`, `C_RXHOST_WORD` and `C_CPL_HOST_WRITE` sit at
  increasing depths along the chain, so a `COVER_DEPTH` run that cannot reach
  the far end still reports where it stopped. If the screen finds the far ones
  unreachable in budget, the cheapest corrections are dropping the ring
  bring-up to five writes (base high and the two pointer writes are all zero
  out of reset), and `RAM_PIPELINE(1)`; the expensive one is moving the far
  observation point from host memory to the receive packet RAM, which costs the
  receive DMA and the whole completion half of the chain.

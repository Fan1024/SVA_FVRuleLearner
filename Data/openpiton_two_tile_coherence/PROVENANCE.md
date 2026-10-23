# openpiton_two_tile_coherence

Two OpenPiton cache tiles -- each an `l15` plus its `l2` slice -- attached to a
real 2x1 P-Mesh, with a memory controller on the off-chip link. Assembled
2026-08-19.

The point of the package is that **a line can be held by two caches at once**.
`tasks/l15_l2_mshr_onehot` cannot reach that state: its formal top has one L1.5
and one L2, so there is no second agent to hold a conflicting permission and
`CATEGORIES.md` category 15 is not admitted by it. Two tiles admit it, and the
coherence invariant necessarily spans state the target does not mention -- the
directory in one L2 slice, the MESI array in the *other* tile's L1.5, and the
invalidate in flight between them.

## Where the sources come from

| what | from | state |
| --- | --- | --- |
| `rtl/openpiton/*` L1.5 + L2 (70 modules) | `tasks/l15_l2_mshr_onehot/rtl/openpiton_l15l2/` | byte-identical except the four files below |
| `rtl/openpiton/*` dynamic node (18 modules) | `tasks/openpiton_pmesh_order/rtl/openpiton_dn/` | byte-identical, every file |
| `rtl/openpiton/credit_to_valrdy.v`, `valrdy_to_credit.v` | an upstream openpiton clone | byte-identical |
| `lists/reset_modes.tcl` | `tasks/l15_l2_mshr_onehot/lists/` | byte-identical |
| `lists/proofgrid_profiles.tcl` | `tasks/openpiton_pmesh_order/lists/` | byte-identical |
| `lists/tc_elab.tcl` | `tasks/l15_l2_mshr_onehot/lists/tc_elab.tcl` | task name, top name, and `set_elab_time_limit 3600s` -> `7200s` |

Nothing in `tasks/l15_l2_mshr_onehot`, `tasks/openpiton_pmesh_order` or
`tasks/openpiton_pmesh_deadlock` was modified; every file above was copied out.

## Scrubbed

Four RTL files differ from the copy in `tasks/l15_l2_mshr_onehot`, and all four
differences are the one configuration change this task is: **two tiles instead
of one**.

1. **`rtl/openpiton/define.tmp.h`** -- `PITON_NUM_TILES 1 -> 2`,
   `PITON_X_TILES 1 -> 2`, `PITON_Y_TILES 1` unchanged. Nothing else in the
   file changed (`diff` is three lines). No module in this package reads those
   macros directly; they are the inputs the two PyHP tables below are rendered
   from, and they are what a reader checks the tables against.

2. **`rtl/openpiton/flat_id_to_xy.v`** -- re-rendered for two tiles. Upstream
   this is PyHP output
   (`piton/design/chip/tile/common/rtl/flat_id_to_xy.v.pyv`) whose loop is
   `for i in range(PITON_NUM_TILES): x = i % PITON_X_TILES; y = i // PITON_X_TILES`,
   so the two-tile rendering is tile 0 at (0,0) and tile 1 at (1,0). The
   one-tile copy names only tile 0 and decodes everything else to X --
   `l2_pipe1_dpath` uses this module to turn a directory sharer or owner id
   into the destination of an `INV_FWD` / `LOAD_FWD` / `STORE_FWD`, so with the
   one-tile table every forward to the second tile would have been addressed to
   X. That is the single most load-bearing scrub in the package.

3. **`rtl/openpiton/xy_to_flat_id.v`** -- the same, in the other direction
   (`xy_to_flat_id.v.pyv`, one outer case arm per x and one inner arm per y,
   flat id = `y*PITON_X_TILES + x`). `l2_pipe1_dpath` uses it to turn a
   requester's coordinates into the directory bit to set.

4. **`rtl/openpiton/network_define.v`** -- this is the
   `tasks/openpiton_pmesh_order` copy rather than the `l15_l2_mshr_onehot` one.
   The two differ in exactly one define: `NETWORK_TOPO_2D_MESH` versus
   `NETWORK_TOPO_XBAR`. No RTL in either tree branches on it; the mesh copy is
   the honest label for a package that wires a 2x1 mesh. One copy is shipped
   because neither `network_define.v` nor `dmbr_define.v` has an include guard
   and both upstream trees ship both files: two copies in one single-unit
   compilation would be two sets of the same macros with no way to see which
   won. For the same reason all the RTL lives in ONE directory,
   `rtl/openpiton/`, rather than the two the sources came from.

## Authored

Nothing below exists in any source package.

- **`rtl/openpiton/define.tmp.vh`** (7 lines) -- a forwarder,
  `` `include "define.tmp.h" ``. The dynamic-node RTL includes `define.tmp.vh`
  and the L1.5/L2 RTL includes `define.tmp.h`; upstream those are two PyHP
  renderings of the same `define.h`, and the two copies in the source packages
  disagree on `PITON_*_TILES`. Both names now reach one header.

- **`rtl/coherence_mesh.v`** (120 lines) -- an X by Y mesh of
  `dynamic_node_top_wrap`, three routers per node. Derived from
  `tasks/openpiton_pmesh_order/rtl/pmesh_top.v`; two things differ.

  * **The west perimeter of column 0 is a port.** OpenPiton's L2 addresses a
    memory request to chip id `{1'b1, ...}`; every router reads that as off-chip
    (`dynamic_input_route_request_calc`: `off_chip = abs_chip_id != my_chip_id_in`)
    and routes toward (`` `OFF_CHIP_NODE_X ``, `` `OFF_CHIP_NODE_Y ``) = (0,0),
    where `` `NOC_FBITS_MEM `` == `3'b010` == `FINAL_WEST` sends it out the west
    link. That link is where a memory controller hangs on a real chip.
    `pmesh_top` ties west valid to 0 and west yummy to 1, which would silently
    swallow every memory request and never answer one.
  * Unused perimeter inputs take constant 0 rather than the node's own output.
    `pmesh_top` feeds a perimeter node's own south/east output back into its
    north/west input with validIn tied low; harmless, but a structural loop.

- **`ft/openpiton_two_tile_coherence_ft.sv`** (745 lines) -- the formal top:
  two tiles on the 2x1 mesh, wired to their routers the way
  `piton/design/chip/tile/rtl/tile.v` wires them (`valrdy_to_credit` in,
  `credit_to_valrdy` out, NoC1 L1.5->L2, NoC2 L2->L1.5, NoC3 L1.5->L2), four
  bounded core sources, and one memory responder on the off-chip link. It also
  declares the observation wires the oracle watches.

- **`sva/openpiton_two_tile_coherence_checker.sv`** (477 lines) -- the
  independent oracle and the four protected coherence targets.

- **`sva/targets_openpiton_two_tile_coherence.sv`** (888 lines) -- 44 candidate
  targets and 30 covers, all fifteen `CATEGORIES.md` categories.

- **`lists/`** -- `tc_elab.files`, `diag_two_tile_coherence.tcl`,
  `targets.txt`; `tc_elab.tcl` derived as recorded above.

- **`taskdef.json`** -- dropped in beside the package rather than added to
  `taskdefs.py`.

## The environment, and why each piece is a legality model

Every environment model restricts nothing a real P-Mesh chip would allow.

- **Four core sources**, two per tile, on the PCX ports. Each holds `val` and
  its payload stable until the L1.5 acks, which is the CCX/PCX contract. Each
  issues an ordinary cacheable load or store, 8 B, never non-cacheable, never
  atomic, never a diagnostic or config access (address type field held at 0).
- **The address window is narrow and shared**: `{30'd0, key[3:0], 6'd0}`, so
  sixteen 64 B-aligned lines, and both tiles draw from the same sixteen. Bit 6
  of the key is the home-tile selector (`` `HOME_ID_ADDR_POS_LOW `` is [11:6],
  `config_system_tile_count` = 2, so `l15_home_encoder` reduces the field to
  address bit 6) and also the low bit of `` `L2_TAG_INDEX `` [8:6]; bit 9 is a
  tag bit. Eight keys live in tile 0's slice and eight in tile 1's, four keys
  share each L1.5 set (index is address bits [7:4]), and the L1.5 is four-way,
  so replacement pressure is reachable without being forced. This is a
  *restriction on the environment*, not an assumption on the DUT: it makes the
  two agents collide on the same lines, which is what the task is about.
- **The memory responder** holds up to 16 requests, which is 2 x
  `` `L2_MSHR_ENTRIES ``, so it cannot be the binding constraint on how many L2
  MSHR entries are busy. It answers at an adversarially chosen time
  (`mem_send`) and addresses the ack back to whichever L2 sent the request,
  read off that request's own flit 2 (`l2_encoder` builds the header as
  {src, addr, dst}, so `` `MSG_SRC_X_ `` in flit 2 sits at the bit positions
  `` `MSG_DST_X `` occupies in flit 0). With two L2 slices there is no other
  way to answer the right one. Every other field of the header, `MSG_MSHRID`
  included, comes back unchanged.
- **Three fairness assumptions** live in the checker and constrain FREE INPUTS
  of the formal top directly (`cpx_ack[0]`, `cpx_ack[1]`, `mem_send`), never a
  derived state predicate, so consistency is immediate: holding all three high
  for all time satisfies them. A core that never drains CPX and a memory that
  never answers are not coherence failures.

Configuration held at the ordinary two-tile single-chip defaults: `csm_en = 0`
(so the home is a pure function of the address, no coherence-domain remap),
`dmbr_l15_stall = 0`, `config_home_alloc_method` = `` `HOME_ALLOC_LOW_ORDER_BITS ``,
chip id 0, `coreid_x` = the tile index, `coreid_y` = 0, BIST idle.

**The diag installs no assumptions.** There is nothing left for it to
constrain; it exists because v5 requires one, and it fails loudly if the
protected target did not elaborate.

## The oracle

`sva/openpiton_two_tile_coherence_checker.sv` maintains a **shadow directory**
of per-line, per-tile permission from packets observed on the two L1.5s' NoC
pins, and **only** from those. It does not read `l2_dir`, `rf_l15_mesi`, an
MSHR, or any other piece of the design's own bookkeeping -- the design's
directory is exactly what a coherence target is supposed to be checking.

    1. a packet framer per tile per channel     -- flit position is this file's
                                                   own count against the
                                                   header's own MSG_LENGTH
    2. an outstanding-request table per tile    -- keyed on the MSG_MSHRID the
                                                   L1.5 put on NoC1, carrying
                                                   the line from that request's
                                                   own address flit; this is
                                                   what lets a one-flit
                                                   DATA_ACK, which carries no
                                                   address, name a line
    3. a revoke queue per tile                  -- pushed at a LOAD_FWD /
                                                   STORE_FWD / INV_FWD header
                                                   plus its address flit,
                                                   popped at a last-subline
                                                   *_FWDACK
    4. sh_excl[tile], sh_shared[tile]           -- one bit per line key

An ack with `` `MSG_MESI `` of E or M gives write permission, S gives read
permission; a popped INV/STORE FWDACK takes all permission away, a popped
LOAD_FWDACK downgrades write to read, and a writeback or writeback guard the
tile issued itself takes it away.

`sva/targets_openpiton_two_tile_coherence.sv` builds five more independent
oracles of its own -- four NoC1 shadow queues (one per source-L1.5/home-L2
pair, the two-agent form of `openpiton_pmesh_order`'s four-queue oracle), an
outstanding-memory-request set keyed on (requesting L2, MSG_MSHRID), a per-tile
outstanding-L1.5-request set, forward/forward-ack conservation counters, and
saturating wait counters -- and reads the checker's shadow directory for the
coherence category.

## design_keep

`taskdef.json` keeps three groups out of the reset cut. The rule is preserve
the instrument, cut the design.

| pattern | why |
| --- | --- |
| `u_checker\.(sh_excl\|sh_shared\|req_live\|req_key\|req_store\|req_open\|req_open_v\|req_open_wbg\|rq_key\|rq_inv\|rq_wr\|rq_rd\|rq_open\|rq_open_v\|rq_open_inv\|n3_is_wb_open\|f1_idx\|f1_len\|f2_idx\|f2_len\|f3_idx\|f3_len)` | the shadow directory and everything that feeds it. Every coherence target IS an assertion about these registers. Cut, `sh_excl[0] & sh_excl[1]` is non-zero at cycle 0 and `T_COHERENCE_NO_TWO_WRITERS` fails for a reason no design can correct. |
| `u_mem\.(hdr_q\|src_q\|q_wr_f\|q_rd_f\|rx_state_f\|rx_left_f\|rx_idx_f\|tx_state_f\|tx_left_f)` | the memory responder is authored environment, not design. Cut, its queue starts non-empty and it emits `*_MEM_ACK` packets for requests that were never made -- unsolicited responses that falsify the request/response targets and corrupt whichever L2 MSHR entry the invented `MSG_MSHRID` names. |
| `ready_sr` | the two-cycle post-reset gate. `dynamic_node_top` registers `reset_in` once, so the routers are still in reset for a cycle after `reset_n` rises. Cut, `ready_sr` starts arbitrary, the core sources inject into a fabric still in reset, and the flits are lost inside the routers rather than by anything the design did. |

Two deliberate non-keeps, recorded because they were considered:

- The `valrdy_to_credit` / `credit_to_valrdy` credit counters are NOT kept.
  They are upstream OpenPiton RTL that a real tile contains, so they are design
  and the cut belongs on them. The consequence is real and is a known caveat:
  cut, a credit counter can start high enough for the formal top to overrun a
  router's input FIFO, which can falsify `T_PROTO_*` and `T_BOUND_*` for a
  reason the design cannot correct. If the screen returns `cex` on those with a
  trace that starts from an overrun credit, that is why.
- `tt_core_source.pending_f` / `payload_f` are NOT kept. An arbitrary start is
  one extra request in flight, which is a state a real core can produce.

## The gate

    uv run python v6_dataset/elab_local.py --task openpiton_two_tile_coherence
    OK: openpiton_two_tile_coherence elaborates

    uv run python v6_dataset/elab_local.py --task openpiton_two_tile_coherence \
        --extra sva/targets_openpiton_two_tile_coherence.sv
    targets_openpiton_two_tile_coherence.sv: 44 labelled assert, 30 labelled cover
    OK: openpiton_two_tile_coherence elaborates with 1 extra file(s)

Slang elaborates 90 modules; the hierarchy was probed to confirm both
`g_tile[0]` and `g_tile[1]` (L1.5 + L2 each), all six `dynamic_node_top`
instances, the six credit transducer pairs and the memory responder are
present. **This is elaboration only. Nothing here has been simulated or proven
-- no target in this package has a verdict.**

## What is not verified, and what to look at first

- The revoke queue pairs a forward with a forward-ack **positionally**, on the
  assumption that OpenPiton's NoC2 is in order point-to-point and that an L1.5
  answers forwards in the order it takes them. If that is wrong the shadow
  directory attributes a revoke to the wrong line and the coherence targets are
  wrong with it. `T_REQRSP_FWDACK_HAS_PENDING_FWD_T0` and
  `T_CONSERV_FWDACK_NEVER_EXCEEDS_FWD_T0` are the two that would show it.
- `T_LIFECYCLE_FWD_ONLY_TO_A_HOLDER_T0` says a forward arriving at a tile names
  a line the shadow says that tile holds. Races between a writeback guard and a
  forward already in flight could make it false; it is written as a target
  precisely so the screen answers the question.
- `T_ORDER_L15_REQUEST_TYPE_PRESERVED_T0` and the `T_UNIQ_L15_MSHRID_*` family
  assume the L1.5's `MSG_MSHRID` low three bits ({threadid, class}) are unique
  among that L1.5's live requests. Writeback guards travel on NoC1 with a
  mshrid too and are not tracked; if they collide with a live load or store id
  the outstanding-request set is wrong.

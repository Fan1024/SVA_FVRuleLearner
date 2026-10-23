FORMAL-VERIFICATION SVA INVENTORY
=================================

This repository contains 33 formal-verification design packages.
For each design below, "selected targets" are the target_labels from
taskdef.json. l15_l2_mshr_onehot has no taskdef.json, so its one target
is taken from PROVENANCE.md and its checker. "All assertions" counts
every labeled assert property statement physically present under sva/.

Repository totals:
  Selected target assertions: 284
  All SVA assertions:          1427
  Files under sva/:            60

corundum_dma_path
-----------------
SVA files: targets_corundum_dma_path.sv
Selected targets: 15
All assertions:   50
Selected target definitions:
  T_ALLOC_CPL_DMA_WRITE_SLOT_LIVE  [corundum_dma_path/sva/targets_corundum_dma_path.sv:617]
  T_ALLOC_ENQ_COMMIT_NAMES_LIVE_OP_P0  [corundum_dma_path/sva/targets_corundum_dma_path.sv:611]
  T_BOUNDRSP_CPL_STATUS_WITHIN_N  [corundum_dma_path/sva/targets_corundum_dma_path.sv:667]
  T_BOUNDRSP_DESC_DELIVERED_WITHIN_N  [corundum_dma_path/sva/targets_corundum_dma_path.sv:664]
  T_BOUNDRSP_FETCH_STATUS_WITHIN_N  [corundum_dma_path/sva/targets_corundum_dma_path.sv:661]
  T_BOUND_CPL_RING_OCCUPANCY  [corundum_dma_path/sva/targets_corundum_dma_path.sv:598]
  T_CONSERV_CPL_HOST_WRITES_LE_REQUESTS  [corundum_dma_path/sva/targets_corundum_dma_path.sv:571]
  T_CONSERV_DEQ_NOT_MORE_THAN_POSTED  [corundum_dma_path/sva/targets_corundum_dma_path.sv:560]
  T_CONSERV_DESC_BEATS_MATCH_LEN  [corundum_dma_path/sva/targets_corundum_dma_path.sv:564]
  T_CONSERV_DESC_DELIVERED_LE_FETCHED  [corundum_dma_path/sva/targets_corundum_dma_path.sv:568]
  T_DATA_CPL_PAYLOAD_TO_HOST  [corundum_dma_path/sva/targets_corundum_dma_path.sv:543]
  T_DEADLOCK_DF_TABLE_DRAINS_WITHIN_N  [corundum_dma_path/sva/targets_corundum_dma_path.sv:674]
  T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N  [corundum_dma_path/sva/targets_corundum_dma_path.sv:671]
  T_REQRSP_CPL_STATUS_TAG_LIVE  [corundum_dma_path/sva/targets_corundum_dma_path.sv:630]
  T_UNIQ_ENQ_OP_TAG_NOT_REUSED_P0  [corundum_dma_path/sva/targets_corundum_dma_path.sv:556]

corundum_dma_path_oraclefree
----------------------------
SVA files: targets_corundum_dma_path.sv
Selected targets: 9
All assertions:   42
Selected target definitions:
  T_ALLOC_ENQ_COMMIT_NAMES_LIVE_OP_P0  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:511]
  T_BOUNDRSP_CPL_STATUS_WITHIN_N  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:579]
  T_BOUNDRSP_DESC_DELIVERED_WITHIN_N  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:576]
  T_BOUNDRSP_FETCH_STATUS_WITHIN_N  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:573]
  T_CONSERV_CPL_HOST_WRITES_LE_REQUESTS  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:463]
  T_CONSERV_DEQ_NOT_MORE_THAN_POSTED  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:452]
  T_CONSERV_DESC_DELIVERED_LE_FETCHED  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:459]
  T_DEADLOCK_DF_TABLE_DRAINS_WITHIN_N  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:589]
  T_UNIQ_ENQ_OP_TAG_NOT_REUSED_P0  [corundum_dma_path_oraclefree/sva/targets_corundum_dma_path.sv:440]

corundum_tx_rx_datapath
-----------------------
SVA files: targets_corundum_tx_rx_datapath.sv
Selected targets: 25
All assertions:   50
Selected target definitions:
  T_ALLOC_TXCPL_TAG_MARKED  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:886]
  T_BOUNDRSP_FETCH_STATUS_WITHIN_N  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:928]
  T_BOUNDRSP_PKT_TO_HOST_WITHIN_N  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:931]
  T_BOUND_DESC_FETCH_INFLIGHT  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:866]
  T_CONSERV_CPL_HOST_LE_CPL_DMA  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:847]
  T_CONSERV_DESC_STREAM_LE_FETCH_OK  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:838]
  T_CONSERV_IFRX_LE_IFTX  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:841]
  T_CONSERV_RXHOST_PKT_LE_IFRX  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:844]
  T_DATA_CPL_ADDR_IS_NEXT_RING_SLOT  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:819]
  T_DATA_CPL_LEN_IS_A_PACKET_LEN  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:822]
  T_DATA_DESC_MATCHES_HOST  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:792]
  T_DATA_IFRX_WORD_SELF_CONSISTENT  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:810]
  T_DATA_IFTX_WORD_ADDR_STEPS_8  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:804]
  T_DATA_IFTX_WORD_SELF_CONSISTENT  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:801]
  T_DATA_MAC0_HALFWORD_PAIR  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:807]
  T_DATA_RXDMA_ADDR_MATCHES_DESC  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:798]
  T_DATA_RXHOST_WORD_ADDR_STEPS_8  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:816]
  T_DATA_RXHOST_WORD_SELF_CONSISTENT  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:813]
  T_DATA_TXDMA_ADDR_MATCHES_DESC  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:795]
  T_DEADLOCK_DF_TABLE_DRAINS_WITHIN_N  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:939]
  T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:936]
  T_FAIR_RX_DESC_REQ_ADMITTED_WITHIN_N  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:923]
  T_FAIR_TX_DESC_REQ_ADMITTED_WITHIN_N  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:920]
  T_ORDER_DESC_STREAM_IS_OLDEST_FETCH  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:781]
  T_ORDER_PKT_PORT0_FIFO  [corundum_tx_rx_datapath/sva/targets_corundum_tx_rx_datapath.sv:784]

cva6_frontend_issue_commit
--------------------------
SVA files: covers_cva6_frontend_issue_commit.sv,targets_cva6_frontend_issue_commit.sv
Selected targets: 1
All assertions:   50
Selected target definitions:
  T_BOUND_STORE_SPEC_QUEUE_LE_DEPTH  [cva6_frontend_issue_commit/sva/targets_cva6_frontend_issue_commit.sv:506]

l15_l2_mshr_onehot
------------------
SVA files: openpiton_l15l2_deadlock_checker.sv
Selected targets: 1
All assertions:   1
Selected target definitions:
  T_L2_MSHR_ONEHOT  [l15_l2_mshr_onehot/sva/openpiton_l15l2_deadlock_checker.sv:86]

l15_l2_mshr_onehot_oraclefree
-----------------------------
SVA files: openpiton_l15l2_deadlock_checker.sv,targets_l15_l2_mshr_onehot.sv
Selected targets: 12
All assertions:   18
Selected target definitions:
  T_ALLOC_NOC1BUF_NO_POP_WHEN_EMPTY  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:268]
  T_ALLOC_NOC1BUF_NO_PUSH_WHEN_FULL  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:260]
  T_CONSERV_NOC1BUF_OCC_EQ_VALIDS  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:232]
  T_CONSERV_NOC1BUF_PUSH_MINUS_POP  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:241]
  T_DEADLOCK_L2_MSHR_POOL_DRAINS_WITHIN_N  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:322]
  T_FAIR_L15_NOC3_ADMITTED_WITHIN_N  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:295]
  T_LIFECYCLE_MSHR_ENTRY_NOT_REWRITTEN_WHILE_OUTSTANDING  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:335]
  T_LIFECYCLE_MSHR_KEY_STABLE_WHILE_OUTSTANDING  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:343]
  T_MUTEX_L2_MSHR_LINE_ONEHOT  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:202]
  T_REQRSP_MEM_REQ_HAS_BUSY_ENTRY  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:275]
  T_UNIQ_L2_MSHR_SETWAY_ONEHOT  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:217]
  T_UNIQ_NOC1BUF_SLOT_NOT_OVERWRITTEN  [l15_l2_mshr_onehot_oraclefree/sva/targets_l15_l2_mshr_onehot.sv:221]

nvdla_bdma_data_order
---------------------
SVA files: nvdla_bdma_data_order_checker.sv,targets_nvdla_bdma_data_order.sv
Selected targets: 14
All assertions:   51
Selected target definitions:
  T_BOUNDRSP_STORE_DRAINS_WITHIN_N  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:456]
  T_BOUND_STORE_BEAT_INDEX  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:380]
  T_BOUND_WRITE_COMMANDS_OWED  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:372]
  T_BOUND_WRITE_DATA_BEATS_OWED  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:376]
  T_DATA_BOTH_ADDRESSES_ARE_LINE_ALIGNED  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:273]
  T_DATA_WRITE_COMMAND_SIZE_IS_ONE_LINE  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:265]
  T_DATA_WRITE_MASK_IS_FULL  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:261]
  T_DATA_XOR_CONSERVED_WHEN_DRAINED  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:257]
  T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:463]
  T_LIFECYCLE_CVIF_NEVER_ADDRESSED_AT_THE_BOUNDARY  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:499]
  T_LIFECYCLE_INTERRUPT_NEVER_ARMED  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:503]
  T_LIFECYCLE_NO_GROUP_DONE_WITHOUT_AN_ARMED_INTERRUPT  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:507]
  T_ORDER_WCMD_NEVER_RUNS_AHEAD_OF_ITS_COMMAND  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:247]
  T_REQRSP_STORE_ONLY_OFFERS_DATA_AFTER_ITS_COMMAND  [nvdla_bdma_data_order/sva/targets_nvdla_bdma_data_order.sv:412]

nvdla_cdp_syncfifo_order
------------------------
SVA files: nvdla_cdp_syncfifo_order_checker.sv,targets_nvdla_cdp_syncfifo_order.sv
Selected targets: 3
All assertions:   47
Selected target definitions:
  T_DATA_ITP_XOR_CONSERVED_WHEN_DRAINED  [nvdla_cdp_syncfifo_order/sva/targets_nvdla_cdp_syncfifo_order.sv:254]
  T_DATA_MUL_XOR_CONSERVED_WHEN_DRAINED  [nvdla_cdp_syncfifo_order/sva/targets_nvdla_cdp_syncfifo_order.sv:246]
  T_DATA_OCVT_XOR_CONSERVED_WHEN_DRAINED  [nvdla_cdp_syncfifo_order/sva/targets_nvdla_cdp_syncfifo_order.sv:250]

nvdla_conv_pipeline
-------------------
SVA files: nvdla_conv_pipeline_checker.sv
Selected targets: 24
All assertions:   48
Selected target definitions:
  T_ALLOC_CBUF_DAT_NO_GRANT_BEFORE_WRITE  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:585]
  T_BOUNDRSP_MEM_DAT_RSP_TAKEN_WITHIN_256  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:663]
  T_BOUND_CBUF_DAT_READS_IN_FLIGHT_LE6  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:559]
  T_BOUND_CBUF_DAT_WR_ADDR_IN_RANGE  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:567]
  T_BOUND_MAC_A_TOKENS_IN_FLIGHT_LE4  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:555]
  T_BOUND_MEM_DAT_REQ_ATOMS_LE256  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:563]
  T_COHERENCE_CBUF_DAT_WT_SAME_LINE  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:712]
  T_CONSERV_MAC_A_TOKENS  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:522]
  T_DATA_CBUF_DAT_LINE_STABLE_WITHOUT_WRITE  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:498]
  T_DATA_CBUF_DAT_READBACK  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:482]
  T_DATA_CBUF_WMB_READBACK  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:490]
  T_DATA_CBUF_WT_READBACK  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:486]
  T_DATA_MAC_A_PD_PRESERVED  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:494]
  T_DEADLOCK_CONV_PIPELINE_PROGRESS_WITHIN_1024  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:671]
  T_DEADLOCK_MEM_DAT_COMMAND_DRAINS_WITHIN_256  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:675]
  T_FAIR_CSC_DAT_PENDING_ACKED_WITHIN_512  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:643]
  T_FAIR_CSC_WT_PENDING_ACKED_WITHIN_512  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:647]
  T_LIFECYCLE_CSB_POSTED_WRITE_IS_SILENT  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:700]
  T_ORDER_MAC_A_PD_IS_QUEUE_HEAD  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:468]
  T_ORDER_MAC_B_PD_IS_QUEUE_HEAD  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:473]
  T_PROTO_MEM_DAT_REQ_STABLE  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:622]
  T_PROTO_SDP_VALID_STABLE  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:631]
  T_UNIQ_MAC_A_NO_OUTPUT_WITHOUT_INPUT  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:506]
  T_UNIQ_MAC_B_NO_OUTPUT_WITHOUT_INPUT  [nvdla_conv_pipeline/sva/nvdla_conv_pipeline_checker.sv:510]

nvdla_mcif_order
----------------
SVA files: nvdla_mcif_order_checker.sv,targets_nvdla_mcif_order.sv
Selected targets: 24
All assertions:   51
Selected target definitions:
  T_ALLOC_CQ_INDEX_IN_RANGE  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:585]
  T_ALLOC_CQ_NO_POP_WHEN_EMPTY  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:589]
  T_BOUNDRSP_EGRESS_DRAINS_WITHIN_N  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:663]
  T_BOUNDRSP_INGRESS_ISSUES_WITHIN_N  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:667]
  T_BOUND_BPT_LATENCY_CREDITS  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:577]
  T_BOUND_CLIENT_HELD_BEATS  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:562]
  T_BOUND_COMMAND_QUEUE_NEVER_WRAPS  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:567]
  T_BOUND_OS_CNT_LE_WINDOW  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:554]
  T_BOUND_PUBLIC_OUTSTANDING_LE_WINDOW  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:558]
  T_CONSERV_CQ_FREE_PLUS_ALLOCATED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:527]
  T_CONSERV_EGRESS_HOLDINGS_ACCOUNTED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:518]
  T_CONSERV_RO_FIFO_HALVES_TRACK  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:531]
  T_DATA_AR_ADDR_IS_HEAD_COMMAND  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:474]
  T_DATA_EG_CONTEXT_IS_SINGLE_FULL_BEAT  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:482]
  T_DATA_EG_WRITE_ENABLE_IS_FULL  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:486]
  T_DATA_XOR_CONSERVED_WHEN_DRAINED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:478]
  T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_N  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:674]
  T_REQRSP_AR_HAS_A_COMMAND  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:608]
  T_REQRSP_CQ_WRITE_NAMES_A_REQUESTING_CLIENT  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:612]
  T_REQRSP_RESPONSE_HAS_A_COMMAND  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:601]
  T_UNIQ_AR_NEVER_INVENTED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:493]
  T_UNIQ_CQ_ENTRY_NOT_DOUBLE_ALLOCATED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:507]
  T_UNIQ_CQ_ENTRY_NOT_DOUBLE_FREED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:511]
  T_UNIQ_RESPONSE_NEVER_INVENTED  [nvdla_mcif_order/sva/targets_nvdla_mcif_order.sv:500]

nvdla_rubik_merge_transpose
---------------------------
SVA files: nvdla_rubik_merge_transpose_checker.sv,targets_nvdla_rubik_merge_transpose.sv
Selected targets: 1
All assertions:   40
Selected target definitions:
  T_DATA_OUTPUT_BYTE_FOLD_MATCHES_ITS_COLUMN  [nvdla_rubik_merge_transpose/sva/targets_nvdla_rubik_merge_transpose.sv:262]

nyuzi_l2_ring_coherence
-----------------------
SVA files: covers_nyuzi_l2_ring_coherence.sv,targets_nyuzi_l2_ring_coherence.sv
Selected targets: 12
All assertions:   49
Selected target definitions:
  T_COH_DINVALIDATE_CLEARS_ALL_L1D  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:921]
  T_CONSERV_FOCUS_RSP_LE_ADM  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:812]
  T_CONSERV_NO_RESPONSE_WHEN_EMPTY  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:806]
  T_DEADLOCK_GLOBAL_PROGRESS_WITHIN_32  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:986]
  T_MUTEX_SNOOP_HIT_ONEHOT  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:757]
  T_OCC_INFLIGHT_LE_12  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:799]
  T_OCC_INFLIGHT_LE_24  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:792]
  T_OCC_PENDING_MISS_CAM_NOT_FULL  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:779]
  T_PROTO_RESPONSE_CORE_LEGAL  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:848]
  T_REQRSP_ICACHE_RESPONSE_HAS_REQUEST  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:711]
  T_REQRSP_RESPONSE_CACHE_TYPE_MATCHES  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:706]
  T_REQRSP_RESPONSE_TYPE_MATCHES  [nyuzi_l2_ring_coherence/sva/targets_nyuzi_l2_ring_coherence.sv:699]

nyuzi_l2_ring_coherence_oraclefree
----------------------------------
SVA files: covers_nyuzi_l2_ring_coherence.sv,targets_nyuzi_l2_ring_coherence.sv
Selected targets: 13
All assertions:   14
Selected target definitions:
  T_REQRSP_ICACHE_RESPONSE_HAS_REQUEST  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:358]
  T_REQRSP_RESPONSE_CACHE_TYPE_MATCHES  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:370]
  T_REQRSP_RESPONSE_TYPE_MATCHES  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:380]
  T_CONSERV_FOCUS_RSP_LE_ADM  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:391]
  T_CONSERV_NO_RESPONSE_WHEN_EMPTY  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:401]
  T_MUTEX_SNOOP_HIT_ONEHOT  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:409]
  T_OCC_PENDING_MISS_CAM_NOT_FULL  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:417]
  T_OCC_INFLIGHT_LE_12  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:429]
  T_OCC_INFLIGHT_LE_24  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:440]
  T_PROTO_RESPONSE_CORE_LEGAL  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:449]
  T_UNIQ_FILL_FIFO_SLOT_UNIQUE  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:460]
  T_COH_DINVALIDATE_CLEARS_ALL_L1D  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:474]
  T_COH_L1D_LINE_IN_ONE_WAY  [nyuzi_l2_ring_coherence_oraclefree/sva/targets_nyuzi_l2_ring_coherence.sv:485]

openpiton_pmesh_order
---------------------
SVA files: openpiton_pmesh_order_scaled_checker.sv,targets_openpiton_pmesh_order.sv
Selected targets: 29
All assertions:   51
Selected target definitions:
  T_BOUND_INFLIGHT_PER_FLOW  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:508]
  T_BOUND_INFLIGHT_TOTAL  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:512]
  T_CONSERVE_INFLIGHT_EQUALS_BUFFERED  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:446]
  T_CONSERVE_NO_STRAY_EGRESS  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:456]
  T_CONSERVE_NO_TRAFFIC_OFF_PATH  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:459]
  T_DEADLOCK_GLOBAL_PROGRESS  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:601]
  T_DEADLOCK_NO_STALLED_BUFFER  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:604]
  T_FAIR_T2_SOUTH_PROC_INPUT  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:575]
  T_FAIR_T2_SOUTH_WEST_INPUT  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:572]
  T_FAIR_T5_SOUTH_NORTH_INPUT  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:578]
  T_FAIR_T5_SOUTH_PROC_INPUT  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:581]
  T_INTEGRITY_EGRESS_FULL_FLIT  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:422]
  T_INTEGRITY_EGRESS_HEADER  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:419]
  T_INTEGRITY_PATH_HEAD_HEADER  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:426]
  T_MUTEX_THANKS_ONEHOT_MESH  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:480]
  T_ORDERING_FLOW0_FIFO  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:397]
  T_ORDERING_FLOW1_FIFO  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:400]
  T_ORDERING_FLOW2_FIFO  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:403]
  T_ORDERING_FLOW3_FIFO  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:406]
  T_ORDERING_LASTHOP_HEAD  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:411]
  T_PROTO_EGRESS_HAS_SOURCE_DATA  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:565]
  T_PROTO_NO_MISROUTED_GRANT  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:550]
  T_REQRSP_CREDIT_LE_INJECTION  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:537]
  T_REQRSP_NO_UNSOLICITED_FLOW  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:533]
  T_RESPONSE_DST_GRANT_LATENCY  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:588]
  T_RESPONSE_EGRESS_DRAIN  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:591]
  T_RESPONSE_SOURCE_CREDIT_RETURN  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:594]
  T_UNIQUE_NO_POP_OF_EMPTY_QUEUE  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:437]
  T_UNIQUE_PERFLOW_DELIVERY_LE_INJECTION  [openpiton_pmesh_order/sva/targets_openpiton_pmesh_order.sv:433]

openpiton_pmesh_waitcycle
-------------------------
SVA files: openpiton_pmesh_deadlock_checker.sv,targets_openpiton_pmesh_waitcycle.sv
Selected targets: 15
All assertions:   51
Selected target definitions:
  T_BOUND_INFLIGHT_TOTAL  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:700]
  T_CONSERVE_INFLIGHT_EQUALS_BUFFERED  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:658]
  T_CONSERVE_SINK_ACCOUNT  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:667]
  T_DEADLOCK_GLOBAL_PROGRESS  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:779]
  T_DEADLOCK_NO_STALLED_ENDPOINT_BUFFER  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:785]
  T_DEADLOCK_NO_STALLED_MESH_BUFFER  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:782]
  T_FAIR_T5_SOUTH_NORTH_INPUT  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:744]
  T_FAIR_T5_SOUTH_PROC_INPUT  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:750]
  T_FAIR_T5_SOUTH_WEST_INPUT  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:747]
  T_ORDER_ALL_FLOWS_FIFO  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:614]
  T_ORDER_FLOW0_FIFO  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:608]
  T_ORDER_FLOW2_FIFO  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:611]
  T_RESPONSE_DST_GRANT_LATENCY  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:763]
  T_RESPONSE_SOURCE_CREDIT_RETURN  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:769]
  T_UNIQ_NO_DELIVERY_WITHOUT_QUEUED  [openpiton_pmesh_waitcycle/sva/targets_openpiton_pmesh_waitcycle.sv:650]

openpiton_two_tile_coherence
----------------------------
SVA files: openpiton_two_tile_coherence_checker.sv,targets_openpiton_two_tile_coherence.sv
Selected targets: 14
All assertions:   48
Selected target definitions:
  T_BOUNDRSP_MEM_ROUND_TRIP_WITHIN_N  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:773]
  T_BOUND_NOC1_PAIR_QUEUE_LE_DEPTH  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:720]
  T_BOUND_REVOKE_QUEUE_LE_DEPTH  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:725]
  T_COHERENCE_HOME_SLICE_OWNS_ITS_LINES  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:822]
  T_DATA_NOC1_LINE_PRESERVED_ACROSS_MESH_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:680]
  T_DEADLOCK_L2_POOL_DRAINS_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:785]
  T_FAIR_MEM_LINK_ADMITTED_WITHIN_N  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:767]
  T_FAIR_NOC1_ADMITTED_WITHIN_N_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:765]
  T_MUTEX_L2_MSHR_LINE_ONEHOT_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:712]
  T_ORDER_MEM_ACK_IN_REQUEST_ORDER  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:671]
  T_ORDER_NOC1_ID_ARRIVES_IN_SEND_ORDER_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:669]
  T_PROTO_NOC1_DATA_STABLE_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:755]
  T_REQRSP_MEM_REQ_NAMES_A_BUSY_ENTRY  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:747]
  T_UNIQ_L2_MSHR_SET_ONEHOT_T0  [openpiton_two_tile_coherence/sva/targets_openpiton_two_tile_coherence.sv:698]

opentitan_spi_device_fifo
-------------------------
SVA files: covers_opentitan_spi_device_fifo.sv,targets_opentitan_spi_device_fifo.sv
Selected targets: 3
All assertions:   50
Selected target definitions:
  T_DATA_ADDRFIFO_POP_EQ_PUSH  [opentitan_spi_device_fifo/sva/targets_opentitan_spi_device_fifo.sv:424]
  T_DEADLOCK_ADDRFIFO_DRAIN_LE_32  [opentitan_spi_device_fifo/sva/targets_opentitan_spi_device_fifo.sv:656]
  T_UNIQ_CMDFIFO_POPS_LE_PUSHES  [opentitan_spi_device_fifo/sva/targets_opentitan_spi_device_fifo.sv:464]

opentitan_tlul_socket_order
---------------------------
SVA files: targets_opentitan_tlul_socket_order.sv
Selected targets: 7
All assertions:   49
Selected target definitions:
  T_BOUND_SEGMENT_NOT_YET_FORWARDED  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:339]
  T_DATA_DEVICE_REQUEST_PAYLOAD_IS_RING_ENTRY  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:276]
  T_DATA_DEVICE_RESPONSE_WORD_IS_RING_ENTRY  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:278]
  T_DATA_HOST_RESPONSE_WORD_IS_RING_HEAD  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:272]
  T_ORDER_DEVICE_REQUEST_IS_RING_ENTRY  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:257]
  T_ORDER_DEVICE_RESPONSE_IS_RING_ENTRY  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:260]
  T_ORDER_HOST_RESPONSE_SOURCE_IS_RING_HEAD  [opentitan_tlul_socket_order/sva/targets_opentitan_tlul_socket_order.sv:253]

pulp_stream_xbar_order
----------------------
SVA files: targets_pulp_stream_xbar_order.sv
Selected targets: 3
All assertions:   41
Selected target definitions:
  T_LOSS_WHOLE_BLOCK_ACCOUNTING  [pulp_stream_xbar_order/sva/targets_pulp_stream_xbar_order.sv:422]
  T_BOUND_PAIR_IN_FLIGHT  [pulp_stream_xbar_order/sva/targets_pulp_stream_xbar_order.sv:438]
  T_BOUND_REFERENCE_RING_OCCUPANCY  [pulp_stream_xbar_order/sva/targets_pulp_stream_xbar_order.sv:440]

serv_rvfi_insn_addi
-------------------
SVA files: insn_addi.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_addi.sv
Selected targets: 3
All assertions:   48
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_addi/sva/targets_serv_rvfi_insn_addi.sv:485]
  T_DATA_ADDI_RD_MATCHES_INDEPENDENT_MODEL  [serv_rvfi_insn_addi/sva/targets_serv_rvfi_insn_addi.sv:597]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_addi/sva/targets_serv_rvfi_insn_addi.sv:465]

serv_rvfi_insn_bge
------------------
SVA files: insn_bge.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_bge.sv
Selected targets: 2
All assertions:   48
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_bge/sva/targets_serv_rvfi_insn_bge.sv:485]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_bge/sva/targets_serv_rvfi_insn_bge.sv:465]

serv_rvfi_insn_jal
------------------
SVA files: insn_jal.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_jal.sv
Selected targets: 2
All assertions:   48
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_jal/sva/targets_serv_rvfi_insn_jal.sv:485]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_jal/sva/targets_serv_rvfi_insn_jal.sv:465]

serv_rvfi_insn_lbu
------------------
SVA files: insn_lbu.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_lbu.sv
Selected targets: 3
All assertions:   49
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_lbu/sva/targets_serv_rvfi_insn_lbu.sv:485]
  T_DATA_LBU_MEM_ADDR_MATCHES_INDEPENDENT_MODEL  [serv_rvfi_insn_lbu/sva/targets_serv_rvfi_insn_lbu.sv:600]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_lbu/sva/targets_serv_rvfi_insn_lbu.sv:465]

serv_rvfi_insn_ori
------------------
SVA files: insn_ori.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_ori.sv
Selected targets: 3
All assertions:   49
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_ori/sva/targets_serv_rvfi_insn_ori.sv:485]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_ori/sva/targets_serv_rvfi_insn_ori.sv:465]
  T_DATA_SERIAL_ADD_EQUALS_PARALLEL_ADD  [serv_rvfi_insn_ori/sva/targets_serv_rvfi_insn_ori.sv:459]

serv_rvfi_insn_sll
------------------
SVA files: insn_sll.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_sll.sv
Selected targets: 2
All assertions:   49
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_sll/sva/targets_serv_rvfi_insn_sll.sv:485]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_sll/sva/targets_serv_rvfi_insn_sll.sv:465]

serv_rvfi_insn_sw
-----------------
SVA files: insn_sw.v,rvfi_insn_check.sv,targets_serv_rvfi_insn_sw.sv
Selected targets: 3
All assertions:   49
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_insn_sw/sva/targets_serv_rvfi_insn_sw.sv:485]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_insn_sw/sva/targets_serv_rvfi_insn_sw.sv:465]
  T_DATA_SW_MEM_ADDR_MATCHES_INDEPENDENT_MODEL  [serv_rvfi_insn_sw/sva/targets_serv_rvfi_insn_sw.sv:599]

serv_rvfi_pc_bwd
----------------
SVA files: rvfi_pc_bwd_check.sv,targets_serv_rvfi_pc_bwd.sv
Selected targets: 2
All assertions:   46
Selected target definitions:
  T_CONSERV_FETCH_MINUS_RETIRE_LE_ONE  [serv_rvfi_pc_bwd/sva/targets_serv_rvfi_pc_bwd.sv:485]
  T_DATA_RF_SOURCE_READBACK  [serv_rvfi_pc_bwd/sva/targets_serv_rvfi_pc_bwd.sv:465]

verilog_axis_arb_mux_order
--------------------------
SVA files: targets_verilog_axis_arb_mux_order.sv
Selected targets: 4
All assertions:   43
Selected target definitions:
  T_ORDER_OUT_BEAT_IS_MERGE_HEAD  [verilog_axis_arb_mux_order/sva/targets_verilog_axis_arb_mux_order.sv:404]
  T_ORDER_OUT_ID_IS_MERGE_HEAD_ID  [verilog_axis_arb_mux_order/sva/targets_verilog_axis_arb_mux_order.sv:406]
  T_DATA_INPUT_FIFO_HEAD_IS_SOURCE_HEAD  [verilog_axis_arb_mux_order/sva/targets_verilog_axis_arb_mux_order.sv:417]
  T_UNIQ_NO_SOURCE_DELIVERED_TWICE  [verilog_axis_arb_mux_order/sva/targets_verilog_axis_arb_mux_order.sv:428]

verilog_axis_width_roundtrip
----------------------------
SVA files: targets_verilog_axis_width_roundtrip.sv
Selected targets: 1
All assertions:   35
Selected target definitions:
  T_ORDER_BUFFERED_WORD_IS_PACKED_HEAD  [verilog_axis_width_roundtrip/sva/targets_verilog_axis_width_roundtrip.sv:275]

verilog_ethernet_fcs_roundtrip
------------------------------
SVA files: targets_verilog_ethernet_fcs_roundtrip.sv
Selected targets: 4
All assertions:   34
Selected target definitions:
  T_ORDER_OUT_BYTE_IS_MID_PAYLOAD_HEAD  [verilog_ethernet_fcs_roundtrip/sva/targets_verilog_ethernet_fcs_roundtrip.sv:277]
  T_DATA_NO_BAD_FCS_REPORTED  [verilog_ethernet_fcs_roundtrip/sva/targets_verilog_ethernet_fcs_roundtrip.sv:290]
  T_DATA_OUT_NEVER_MARKED_BAD  [verilog_ethernet_fcs_roundtrip/sva/targets_verilog_ethernet_fcs_roundtrip.sv:292]
  T_CONSERV_BYTES_IN_EQ_OUT_PLUS_INFLIGHT  [verilog_ethernet_fcs_roundtrip/sva/targets_verilog_ethernet_fcs_roundtrip.sv:310]

verilog_ethernet_mac_datapath
-----------------------------
SVA files: targets_verilog_ethernet_mac_datapath.sv
Selected targets: 13
All assertions:   48
Selected target definitions:
  T_ALLOC_ARB_GRANT_BACKED  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:572]
  T_BOUNDRSP_MACTX_STALL_BOUNDED  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:629]
  T_BOUND_HDRFIFO0_INFLIGHT  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:551]
  T_BOUND_PAYFIFO0_INFLIGHT  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:554]
  T_CONSERV_HDRPAY_LOCKSTEP_IN_FLOW0  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:513]
  T_CONSERV_HDRPAY_LOCKSTEP_OUT_FLOW0  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:522]
  T_CONSERV_MON_LE_INJECTED  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:479]
  T_CONSERV_RXAXIS_LE_RXGOOD  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:483]
  T_CONSERV_RX_FRAME_ACCOUNT  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:491]
  T_LIFECYCLE_DEMUX_ROUTES_WHOLE_FRAME  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:674]
  T_UNIQ_HDRFIFO0_OUT_LE_IN  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:466]
  T_UNIQ_MON_FRAMES_LE_RXAXIS  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:473]
  T_UNIQ_PAYFIFO0_OUT_LE_IN  [verilog_ethernet_mac_datapath/sva/targets_verilog_ethernet_mac_datapath.sv:469]

wb2axip_axi3_reorder
--------------------
SVA files: targets_wb2axip_axi3_reorder.sv
Selected targets: 8
All assertions:   35
Selected target definitions:
  T_BOUND_PER_ID_LIVE_LE_SEVENTEEN  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:309]
  T_BOUNDRSP_HEAD_PACKET_BEAT_WITHIN_N  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:341]
  T_CONSERV_PER_ID_LIVE_SUMS_TO_INFLIGHT  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:291]
  T_DEADLOCK_AW_PORT_UNBLOCKED_WITHIN_N  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:350]
  T_DEADLOCK_SOME_BOUNDARY_MOVES_WITHIN_N  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:348]
  T_ORDER_OUT_LAST_ON_FOURTH_BEAT  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:262]
  T_REQRSP_PACKETS_COMPLETED_LE_AW_ACCEPTED  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:325]
  T_UNIQ_OUT_COUNT_LE_IN_COUNT  [wb2axip_axi3_reorder/sva/targets_wb2axip_axi3_reorder.sv:280]

wb2axip_axi3_reorder_oraclefree
-------------------------------
SVA files: targets_wb2axip_axi3_reorder.sv
Selected targets: 9
All assertions:   45
Selected target definitions:
  T_ORDER_ID_FRAME_BALANCE  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:207]
  T_ORDER_ID_FRAME_BALANCE_WITH_OUT_REG  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:209]
  T_ORDER_ID_LAST_SPACING_EXACT  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:211]
  T_ORDER_ID_HEAD_RUN_LE_THREE  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:213]
  T_ORDER_ID_TAIL_RUN_LE_THREE  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:215]
  T_ORDER_ID_RESUMES_AT_PACKET_START  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:217]
  T_ORDER_OPEN_PACKET_RESIDUE_BOUNDED  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:219]
  T_DATA_ID_LAST_COUNT_LE_FOUR  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:231]
  T_DATA_TOTAL_LAST_COUNT_LE_SEVEN  [wb2axip_axi3_reorder_oraclefree/sva/targets_wb2axip_axi3_reorder.sv:233]


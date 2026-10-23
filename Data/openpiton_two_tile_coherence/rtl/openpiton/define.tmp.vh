// define.tmp.vh -- AUTHORED forwarder for tasks/openpiton_two_tile_coherence.
//
// The OpenPiton dynamic-node RTL includes "define.tmp.vh" and the L1.5/L2 RTL
// includes "define.tmp.h". Upstream those are two PyHP renderings of the same
// define.h, and in a single-unit compilation two copies would be two sets of the
// same 500 macros with different PITON_*_TILES. One header, reached under both
// names, removes the question of which one won.
`include "define.tmp.h"

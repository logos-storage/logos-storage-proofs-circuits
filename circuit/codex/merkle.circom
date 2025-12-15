pragma circom 2.0.0;

include "poseidon2_compr.circom";
include "misc.circom";

//------------------------------------------------------------------------------

//
// reconstruct the Merkle root using a Merkle inclusion proof
//
// parameters:
//  - depth: the depth of the Merkle tree = log2( numberOfLeaves )
//
// inputs and outputs:
//  - leaf:        the leaf hash
//  - pathBits:    the linear index of the leaf, in binary decomposition (least significant bit first)
//  - lastBits:    the index of the last leaf (= nLeaves-1), in binary decomposition
//  - maskBits:    the bits of the the mask `2^ceilingLog2(size) - 1`
//  - merklePath:  the Merkle inclusion proof (required hashes, starting from the leaf and ending near the root)
//  - recRoot:     the reconstructod Merkle root
//
// NOTE: we don't check whether the bits are really bits, that's the
//       responsability of the caller!
//
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
//
// Merkle tree convention: Here we use a Logos-Storage-specific "safe" Merkle tree convention.
//
// This uses a "keyed compression function", where the key depends on:
// 
//   - whether we are in the bottommost layer or not
//   - whether the node we are dealing with has 1 or 2 children (odd or even node)
// 
// These are two bits, encoded as numbers in the set {0,1,2,3} 
// (the lowest bit is 1 if it's the bottom layer, 0 otherwise; the next bit 
// is 1 if it's an odd node, 0 if even node). Furthermore:
// 
//   - in case of an odd node with leaf x, we apply the compression to the pair (x,0)
//   - in case of a singleton input (the whole Merkle tree is built on a single field element), we also apply one compression
//   - the keyed compression is defined as applying the permutation to the triple (x,y,key), and extracting the first component of the resulting triple
//
//

template RootFromMerklePath( maxDepth ) {

  signal input  leaf;
  signal input  pathBits[ maxDepth ];       // bits of the linear index
  signal input  lastBits[ maxDepth ];       // bits of the last linear index `= size-1`
  signal input  maskBits[ maxDepth+1 ];     // bit mask for `2^ceilingLog(size) - 1`
  signal input  merklePath[ maxDepth ];
  signal output recRoot;

  // in case of a singleton tree, we receive maskBits = [0,0,0,...,0]
  // but what we really need is [1,0,0,0,...,0]
  // maybe it's the best to fix that here
  //
  // this is a bit of hackish, but because we always expect [1,1,...,1,0,0,...,0] anyway,
  // we can just set the first entry to 1 and that should fix this issue.
  //
  signal maskBitsCorrected[ maxDepth + 1];
  maskBitsCorrected[0] <== 1;
  for(var i=1; i<=maxDepth; i++) { maskBitsCorrected[i] <== maskBits[i]; }

  // the sequence of reconstructed hashes along the path
  signal aux[ maxDepth+1 ];
  aux[0] <== leaf;

  // Determine whether nodes from the path are last in their row and are odd,
  // by computing which binary prefixes of the index are the same as the
  // corresponding prefix of the last index.
  // This is done in reverse bit order, because pathBits and lastBits have the
  // least significant bit first.
  component eq[ maxDepth ];
  signal isLast[ maxDepth+1 ];
  isLast[ maxDepth ] <== 1;
  for(var i=maxDepth-1; i>=0; i--) {
    eq[i] = IsEqual();
    eq[i].A <== pathBits[i];
    eq[i].B <== lastBits[i];
    isLast[i] <== isLast[i+1] * eq[i].out;
  }

  // compute the sequence of hashes
  signal switch[ maxDepth ];
  component comp[ maxDepth ];
  for(var i=0; i<maxDepth; i++) {

    var bottom = (i==0) ? 1 : 0;                // is it the bottom layer?
    var odd    = isLast[i] * (1-pathBits[i]);   // is it an odd node?

    comp[i] = KeyedCompression();

    var L = aux[i];
    var R = merklePath[i];

    // based on pathBits[i], we switch or not

    switch[i]      <== (R-L) * pathBits[i];
    comp[i].key    <== bottom + 2*odd;
    comp[i].inp[0] <== L + switch[i];
    comp[i].inp[1] <== R - switch[i];

    comp[i].out ==> aux[i+1];
  }

  // now we need to select the right layer from the sequence of hashes
  var sum = 0;
  signal prods[maxDepth];
  for(var i=0; i<maxDepth; i++) {
    prods[i] <== (maskBitsCorrected[i] - maskBitsCorrected[i+1]) * aux[i+1];
    sum += prods[i];
  }
  recRoot <== sum;
}

//------------------------------------------------------------------------------


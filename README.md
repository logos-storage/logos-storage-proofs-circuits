
Logos Storage Proofs for the MVP
================================

This document describes the storage proof system for the Codex 2023 Q4 MVP.


Repo organization
-----------------

- `README.md` - this document
- `circuit/` - the proof circuit (`circom` code)
- `reference/haskell/` - Haskell reference implementation of the proof input generation
- `reference/nim/proof_input/` - Nim reference implementation of the proof input generation
- `reference/nim/testvectors/` - Nim script to generate test vectors for Poseidon2 sponge hash
- `test/` - tests for (some parts of the) circuit (using the `r1cs-solver` tool)
- `workflow/` - description and script for the full proof workflow


Setup
-----

We assume that a user dataset is split into `nSlots` number of (not necessarily 
uniformly sized) "slots" of size `slotSize`, for example 10 GB or 100 GB or even
1,000 GB (for the MVP we may chose a smaller sizes). The slots of the same dataset 
are spread over different storage nodes, but a single storage node can hold several 
slots (of different sizes, and belonging to different datasets). The slots themselves
can be optionally erasure coded, but this does not change the proof system, only 
the robustness of it.

We assume the slots are split into `nCells` number of fixed, uniformly sized
"cells" of size `cellSize`, for example 2048 bytes. Note that `nCells` can
depend on the particular slot. For the initial version, we assume 
that these numbers are powers of two (especially `nCells`). Worst case we
can just pad the data to achieve this (it probably makes more sense to pad
_before_ the erasure coding, even though this increases the computational cost).
Note that we can simply calculate:

    nCells = slotSize / cellSize

We hash each cell independently, using the sponge construction with Poseidon2 
(see below for details).

The cells are then organized to `blockSize = 64kb` blocks, each block containing
`blockSize / cellSize = 32` cells. This is for compatibility with the networking
layer, which use larger (right now 64kb) blocks. For each block, we compute a
block hash by building a depth `5 = log2(32)` complete Merkle tree, using again 
Poseidon2 hash, with the Merkle tree conventions described below. 

Then on the set of of block hashes in a slot (we have `slotSize / blockSize` many 
ones), we build another (big) Merkle tree, whose root will identify the slot, 
which we call the the "slot root", and is denoted by `slotRoot`.

Then for a given dataset, containing several slots, we can build a third binary 
Merkle tree on the top of its slot roots, resulting in the "dataset root" (note:
this is not the same as the SHA256 hash associated with the original dataset 
uploaded by the user). Grafting these Merkle trees together we get a big dataset 
Merkle tree; however one should be careful about the padding conventions 
(it makes sense to construct the dataset-level Merkle tree separately, as `nSlots`
may not be a power of two, and later maybe `nCells` and `nBlocks` won't be
power-of-two either).

The dataset root is a commitment to the whole (erasure coded) dataset, and will 
be posted on-chain, to ensure that the nodes really store its data and not something else.
Optionally, the slot roots can be posted on-chain, but this seems to be somewhat
wasteful.


Hash function
-------------

For the MVP we will use the Poseidon2 hash function, specialized to state size
`t = 3` field elements, and to the alt-bn128 elliptic curve's scalar field, which 
has size

  r = 21888242871839275222246405745257275088548364400416034343698204186575808495617

For more details about this curve, see [BN254 For The Rest Of Us](https://hackmd.io/@jpw/bn254).
Remark: we have `2^253 < r < 2^254`.

For more details about the Poseidon2 hash, see

- [the Poseidon2 paper](https://eprint.iacr.org/2023/323)
- [the reference implementation](https://github.com/HorizenLabs/poseidon2)

### Data encoding convention

Poseidon2 hash works not over sequence of bytes, but field elements. Hence we
need to convert the data to be hashed to a sequence of field elements.

Note that the field size is approximately 254 bits, so a field element can store 
31 bytes of data but cannot store 32 bytes. Hence we have to split up our data
into 31 bytes "hash chunks", then encode these as field elements. We will use
little-endian byte convention to get from 31 bytes to the _standard form_ of 
a field element, that is, the 31 little-endian bytes encode the number `a`
where `0 <= a < 2^248 < r < 2^254` is the standard representation of a field element.
For padding the last field element use the so-called `10*` strategy: That means
_always_ append a single `0x01` byte, and then pad with the minimum number
of zero bytes so that the final padded length is a multiple of 31.

It's probably better to choose the standard representation of field elements, 
because most standard tools like circom use that; even though choosing the 
Montgomery form would be a tiny bit more efficient (but the difference is very
small, the hashing will dominate the costs anyway).

### Compression and sponge

Poseidon2 offers essentially two API functions: a so called _compression function_
which takes 2 field elements and returns 1; this can be used to build binary
Merkle trees. And a more complex _sponge construction_ for linear hashing,
which can hash an arbitrary sequence of field elements into a single (or several) 
field element(s). 

The sponge can have versions with different "rate" parameters, and the compression
function is more generally a parametric family of functions, which I call a _keyed 
compression function_.

While we could always use a Merkle tree instead of the sponge, in the sponge
construction we can use `rate = 2` with a target of 128-bit security level, which 
in practice means twice as fast; so we should use that for hashing the cells.

Conventions to decide:

- padding (especially important for `rate > 1`)
- conversion from bytes to field elements (see above)
- initialization vector

We propose again the padding strategy `10*` (but here we are talking about field
elements, not bytes!), and an initialization vector `(0,0,domSep)` where `domSep`
(short for "domain separation"), the initial value for the "capacity" part of the 
sponge, is defined as 

    domSep (old) := 2^64 + 256*t + rate
    domSep (new) := 2^64 + 2^24*padding + 2^16*inputType + 2^8*t + rate

Here `inputType` can be:

- 1: input is a sequence of bits
- 8: input is a sequence of bytes
- 254: input is a sequence of BN254 field elements

And `padding` (the padding strategy can be):

- 1: the `10*` padding strategy, applied to a sequence of field elements
- 16: the `10*` padding strategy, applied to a sequence of bytes (or bits)
- 17: the `10*` padding strategy applied first to bytes (to a multiple of 31 bytes), then also to the resulting field element sequence
- 255: no padding


Parameters
----------

Parameters should be set based on bechmarks and other external constraints,
but already we can have some preliminary targets. If we use a slot Merkle tree
of depth between 16-32, and sponge hash with a rate of 2, then the Merkle 
inclusion proof cost will be approximately in balance with the cell hashing
cost if the cell size is 1024-2048 bytes (34-67 field elements).

If we use 2048 byte cells, then `nCells = 8192*8192 = 2^26` gives a slot size
of 128 Gb, which looks like a good compromise target slot size (we don't want
it to be too small, because then the number of slot proofs per node will be
too big; but we don't want it to be too big either, because that's inflexible).
The maximum slot size with cell size of 2048 and a depth of 32 (corresponding
to 2D erasure code is of size `2^16 x 2^16`, see below) is `2^(32+11) = 2^43 = 8 Tb`.

### 2D erasure coding

We need to use 2D erasure coding inside a slot, because while 1D would be better,
the required K,N parameters of the EC would be too big. Furthermore, we don't
want too big storage overhead, so the idea is to use `K ~= 2/3 * N`
(with `N` being a power of two). With such a setting, we can store the
original `K x K` matrix and the small `(N-K) x (N-K)` matrix, and reconstruct
the rest real-time. This particular parameter setting gives us a storage overhead 
of `25%` (of course we can tune the parameters, this is just an example).

Note that the EC rate does not affect the proof system itself, only the required
number of samples to achieve a given target detection probability.

With the above setting (EC rate = 2/3), we need 117 samples to achieve 6 nines
of detection probability. Sampling a single 2048 cell with sponge rate 2
means approx 34 Poseidon2 permutation calls, while computing the root of
a depth 26 Merkle path is another 26 such calls. Finally computing the index
needs 2 calls and an extra cost similar to approx 3 calls, so we have about
65 calls per sample, each about 250 constraints. So in total we have about
`117 * 65 * 250 ~= 1.9 million` constraints, or equivalent to hashing about
`235 kb` of data with a binary Merkle tree or with a sponge of rate 1.


Sampling
--------

Given a slot of a dataset, we want to check `nSamples` randomly selected
cells, to see whether they are still stored by the node. We expect `nSamples`
to be in the range 20-200.

To be able to do this, we need to compute:

- the indices of the selected cells (or Merkle leaves)
- the hashes of the selected cells
- the Merkle paths from these hashes up to the slot root (Merkle proofs)
- the number of cells in the slot (this is because of our particular Merkle 
  tree construction, but we will need it anyway to compute the indices)
- the (single) Merkle path from the slot root to the dataset root.

To be able to sample randomly, we need some external source of entropy; for
this, presumably a block hash of some public blockchain (eg. Ethereum) will
be used. It can be convenient to have the entropy in the form a field element;
for this we can simply take the block hash `modulo r`. While this gives a
somewhat non-uniform probability distribution, in practice this should not
cause any issue. Alternatively, we could just keep 31 bytes of the block hash and
interpret it as a field element, giving 248 bits of uniform entropy.

We propose the following function to compute the indices of the selected cells:

    idx = H( entropy | slotRoot | counter ) `mod` nCells

where `counter` iterates over the range `[1..nSamples]`, `H` is our hash
function (right now Poseidon2 sponge with `rate = 2` and `10*` padding strategy), 
and `|` denotes concatenation (in this case the input is just 3 field elements).


Circuit
-------

For the MVP, we build a monolithic circuit / R1CS instance for proving all
the samples in single slot; then use Groth16 to prove it.

Public inputs:

- dataset root
- slot index within the dataset
- entropy (public randomness)

Private inputs:

- the slot root 
- number of cells in the slot 
- the number of slots in the dataset
- the underlying data of the cells, as sequences of field elements
- the Merkle paths from the leaves (the cell hashes) to the slot root
- the Merkle path from the slot root to the dataset root

Computation:

- compute the cell indices from the slot root and the entropy
- compute the cell hashes from the cell data
- from the cell hashes, using the provided Merkle paths, recompute the slot root
- compare the reconstructed slot root to the slot root given as private input
- from the slot root, using the provided Merkle path, recompute and check the
  dataset root

Note that given the index of a leaf, we can compute the left-right zig-zag
of the corresponding Merkle path, simply by looking at the binary decomposition.
So the Merkle paths will only consist lists of hashes.


Merkle tree conventions
-----------------------

We use the same "safe" Merkle tree construction across the codebase. This uses
a "keyed compression function", where the key depends on:

- whether we are in the bottommost layer or not
- whether the node we are dealing with has 1 or 2 children (odd or even node)

These are two bits, encoded as numbers in the set `{0,1,2,3}` (the lowest bit is
1 if it's the bottom layer, 0 otherwise; the next bit is 1 if it's an odd node,
0 if even node). Furthermore:

- in case of an odd node with leaf `x`, we apply the compression to the pair `(x,0)`
- in case of a singleton input (the whole Merkle tree is built on a single field
  element), we also apply one compression
- the keyed compression is defined as applying the permutation to the triple 
  `(x,y,key)`, and extracting the first component of the resulting triple

In case of SHA256, we could use a compression functions of the form
`SHA256(x|y|key)`, where `x,y` are 32 byte long hashes, and `key` is a single
byte. Since SHA256 already does some padding internally, this has the same
cost as computing just `SHA256(x|y)`.


Network blocks vs. cells
------------------------

The networking layer uses 64kb "blocks", while the proof layer uses 2kb "cells".
To make these compatible, the way we define a hash of a 64kb block is:

- split the 64kb data into 32 smaller 2kb cells;
- hash these cells (with Poseidon2 sponge, rate=2, and `10*` padding);
- build a depth 5 complete binary Merkle tree on those hashes, with the above
  conventions. The resulting Merkle root will be the hash of the 64kb block.

Then we build a big Merkle tree on these block hashes, again with the above
conventions, resulting in the slot root.



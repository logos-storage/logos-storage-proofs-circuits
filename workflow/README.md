
Guide though the whole proof workflow
-------------------------------------

The workflow described below is implemented with shell scripts in this directory.
So the below is more like an explanation.

To run the full workflow:

- set the parameters by editing `params.sh`
- run `setup.sh` to do the circuit-specific setup
- run `prove.sh` to generate input, compute witness and create (and verify) the proof

NOTE: the examples below assume `bash`. In particular, it won't work with `zsh` 
(which is the dafault on newer macOS)! Because, you know, reasons...

To have an overview of what all the different steps and files are, see [PROOFS.md](PROOFS.md).

### Some benchmarks

Approximate time to run this on an M2 macbook pro (8+4 cores), with 10 samples:

- compiling the circuit: 8 seconds 
- circuit-specific setup (with 1 contributor): 85 seconds
- size of the `.zkey` file (only 1 contributor): 110 megabytes
- generating the witness (WASM): 0.3 seconds
- proving with `snarkjs` (slow): 7.7 seconds
- proving wiht `zikkurat` (single threaded!): 13 seconds
- proving with `arkworks`: 4.4 seconds (loading the zkey: 6 seconds)
- proving with `nim-groth16` (old version): 2 seconds

Same with 50 samples:

- compiling: 37 seconds
- circuit-specific setup: ~430 seconds
- `.zkey` file: 525 megabytes
- generating the witness (WASM): 1.2 seconds
- proving with `snarkjs`: 36 seconds
- proving wiht `zikkurat` (single threaded!): 52 seconds
- proving with `arkworks`: 19.8 seconds (loading the zkey: 33 seconds)
- proving with `nim-groth16` (old version): 9.4 seconds

And with 100 samples:

- compiling: 76 seconds
- circuit-specific setup: ~1050 seconds
- `.zkey` file: 1050 megabytes
- generating the witness (WASM): 2.3 seconds
- proving with `snarkjs`: 76 seconds
- proving wiht `zikkurat` (single threaded!): 102 seconds
- proving with `arkworks`: 41 seconds (loading the zkey: 66 seconds)
- proving with `nim-groth16` (old version): 18 seconds

TODO: 

- [x] add `arkworks` prover
- [ ] add `rapidsnarks` prover (doesn't run on ARM...)
- [ ] update `nim-groth16` to `constantine-0.1` (should be faster because no workarounds)
- [ ] add multithreading to `zikkurat`

### Preliminaries

- install `circom`, `snarkjs`, `rapidsnark`: <https://docs.circom.io/getting-started/installation>
- optionally install `circom-witnesscalc`: <https://github.com/iden3/circom-witnesscalc/>
- install Nim: <https://nim-lang.org/>

Build the Nim cli proof input generator:

    $ cd ../reference/nim/proof_input/
    $ nimble build -d:release cli
    $ cd ../../../workflow

### Powers of tau setup

To fetch the ptau file, you have next few options:

1. Run the `ptau.sh` script inside the `workflow` folder. (You can modify the power of ptau inside `./params.sh` file on `PTAU_POWER` variable)

2. Manually download a ready-to-use "powers of tau" setup file (section 7), or generate one
   youself using `snarkjs` (sections 1..7), see the README here: <https://github.com/iden3/snarkjs>
   Size `2^21` (file size about 2GB) should be big enough:

Note: generating this yourself will probably take quite a long time.

### Set the parameters

There are quite a few parameters (run `cli --help` too see them), it's probably
best to collect them into a parameter file. Check out `params.sh` and `cli_args.sh` 
to see one way to do that.

You can edit `params.sh` to your taste before running the workflow scripts.

### Compile the circuit

Create a build directory so we don't pollute the repo:

    $ mkdir -p build
    $ cd build

After that, the first real step is to create the main component:

    $ source ../cli_args.sh && ../../reference/nim/proof_input/cli $CLI_ARGS -v --circom="proof_main.circom"

Then compile the circuit:

    $ export CIRCUIT_LIBDIRS="-l../../circuit/lib -l../../circuit/poseidon2 -l../../circuit/codex"
    $ circom --r1cs --wasm --O2 ${CIRCUIT_LIBDIRS} proof_main.circom

### Optionally extract the witness computation graph

    $ build-circuit proof_main.circom proof_main_graph.bin ${CIRCUIT_LIBDIRS}

### Do the circuit-specific setup

See the [`snarkjs` README](https://github.com/iden3/snarkjs) for an overview of
the whole process.

    $ snarkjs groth16 setup proof_main.r1cs ../../ceremony/powersOfTau28_hez_final_21.ptau proof_main_0000.zkey
    $ snarkjs zkey contribute proof_main_0000.zkey proof_main_0001.zkey --name="1st Contributor Name"

NOTE: with large circuits, javascript can run out of heap. You can increase the
heap limit with:

    $ NODE_OPTIONS="--max-old-space-size=8192" snarkjs groth16 setup <...>

You can add more contributors here if you want.

Finally rename the last contributions result and export the verification key:

    $ rm proof_main_0000.zkey
    $ mv proof_main_0001.zkey proof_main.zkey
    
    $ snarkjs zkey export verificationkey proof_main.zkey proof_main_verification_key.json

NOTE: You have redo all the above if you change any of the five parameters the circuit 
depends on (these are: maxdepth, maxslots, cellsize, blocksize, nsamples).

### Generate an input to the circuit

    $ source ../cli_args.sh && ../../reference/nim/proof_input/cli $CLI_ARGS -v --output=input.json

### Generate the witness

    $ cd proof_main_js
    $ time node generate_witness.js proof_main.wasm ../input.json ../witness.wtns
    $ cd ..

### Create the proof

Using `snarkjs` (very slow, but more portable):

    $ snarkjs groth16 prove proof_main.zkey witness.wtns proof.json public.json

Or using `rapidsnark` (fast, but not very portable):

    $ rapidsnark proof_main.zkey witness.wtns proof.json public.json

Or using `nim-groth16` (experimental):

    $ nim-groth16 -p -z=proof_main.zkey -w=witness.wtns -o=proof.json -i=public.json
    
The output of this step will consist of:

- `proof.json` containing the proof itself
- `public.json` containing the public inputs

### Verify the proof (on CPU)

    $ snarkjs groth16 verify proof_main_verification_key.json public.json proof.json

### Generate solidity verifier contract

    $ snarkjs zkey export solidityverifier proof_main.zkey verifier.sol


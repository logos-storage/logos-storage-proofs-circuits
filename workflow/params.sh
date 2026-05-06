#!/bin/bash

MAXDEPTH=32        # maximum depth of the slot tree 
MAXSLOTS=256       # maximum number of slots  
CELLSIZE=2048      # cell size in bytes 
BLOCKSIZE=65536    # block size in bytes 
NSAMPLES=5         # number of samples to prove

ENTROPY=1234567    # external randomness
SEED=12345         # seed for creating fake data

NSLOTS=11          # number of slots in the dataset
SLOTINDEX=3        # which slot we prove (0..NSLOTS-1)
NCELLS=512         # number of cells in this slot

PTAU_POWER=21
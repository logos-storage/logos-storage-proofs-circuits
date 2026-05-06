#!/bin/bash

ORIG=`pwd`

source ./params.sh

NIMCLI_DIR="${ORIG}/../reference/nim/proof_input/"
PTAU_DIR="${ORIG}/../ceremony"

CIRCUIT_ROOT="${ORIG}/../circuit/"
CIRCUIT_PRF_DIR="${CIRCUIT_ROOT}/codex/"
CIRCUIT_POS_DIR="${CIRCUIT_ROOT}/poseidon2/"
CIRCUIT_LIB_DIR="${CIRCUIT_ROOT}/lib/"

PTAU_FILE="powersOfTau28_hez_final_${PTAU_POWER}.ptau"
PTAU_PATH="${PTAU_DIR}/${PTAU_FILE}"

CIRCUIT_MAIN="proof_main"

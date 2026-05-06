#!/bin/bash

source ./paths.sh
source ./params.sh

PTAU_URL=https://storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_${PTAU_POWER}.ptau

mkdir -p ${PTAU_DIR}

if [ -f ${PTAU_PATH} ]; then
  echo "${PTAU_FILE} download already Completed!"
  exit 0
else
  echo "Downloading ${PTAU_FILE}"
  curl ${PTAU_URL} --output ${PTAU_PATH} --progress-bar
  echo "${PTAU_FILE} download Completed!"
fi
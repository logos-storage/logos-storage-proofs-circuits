
version       = "0.0.1"
author        = "Balazs Komuves"
description   = "reference implementation for generating the proof inputs"
license       = "MIT or Apache-2.0"
srcDir        = "src"
bin           = @["cli"]
#bin           = @["cli","testmain"]

requires "nim >= 1.6.0"
requires "https://github.com/mratsim/constantine#bc3845aa492b52f7fef047503b1592e830d1a774"
requires "https://github.com/logos-storage/nim-poseidon2#4e2c6e619b2f2859aaa4b2aed2f346ea4d0c67a3"
requires "https://github.com/logos-storage/nim-goldilocks-hash#bd5b805b80b6005a3e5de412dec15783284d205d"
#requires "goldilocks_hash == 0.0.1"

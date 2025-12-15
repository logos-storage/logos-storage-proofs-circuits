# Package

version       = "0.1.0"
author        = "Balazs Komuves"
description   = "test vectors using the nim-poseidon2 library"
license       = "MIT"
srcDir        = "src"
bin           = @["testvectors"]

# Dependencies

requires "nim >= 1.6.0"
requires "https://github.com/mratsim/constantine#ab6fa6ae1bbbd1b10071a92ec209b381b5d82511"
requires "https://github.com/logos-storage/nim-poseidon2#8a54c69032a741160bbc097d009e45a8b5e4d718"

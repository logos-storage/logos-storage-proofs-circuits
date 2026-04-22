
module Poseidon2.Example where

--------------------------------------------------------------------------------

import ZK.Algebra.Curves.BN128.Fr.Mont (Fr)

import Poseidon2.Permutation

--------------------------------------------------------------------------------

-- BN254 example test vector
exInput, exOutputOld, exOutputNew :: (Fr,Fr,Fr)
exInput = (0,1,2) 

exOutputOld = 
  ( 0x30610a447b7dec194697fb50786aa7421494bd64c221ba4d3b1af25fb07bd103 
  , 0x13f731d6ffbad391be22d2ac364151849e19fa38eced4e761bcd21dbdc600288 
  , 0x1433e2c8f68382c447c5c14b8b3df7cbfd9273dd655fe52f1357c27150da786f 
  )

exOutputNew = 
  ( 0x0bb61d24daca55eebcb1929a82650f328134334da98ea4f847f760054f4a3033
  , 0x303b6f7c86d043bfcbcc80214f26a30277a15d3f74ca654992defe7ff8d03570
  , 0x1ed25194542b12eef8617361c3ba7c52e660b145994427cc86296242cf766ec8
  )

katsOld :: Bool  
katsOld = permutation HorizenLabsOld exInput == exOutputOld

katsNew :: Bool  
katsNew = permutation HorizenLabsNew exInput == exOutputNew

--------------------------------------------------------------------------------

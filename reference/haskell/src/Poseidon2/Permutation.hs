
-- | The Poseidon2 permutation

{-# LANGUAGE BangPatterns #-}
module Poseidon2.Permutation where

--------------------------------------------------------------------------------

import ZK.Algebra.Curves.BN128.Fr.Mont (Fr)

import qualified Poseidon2.RoundConstsOld as Old
import qualified Poseidon2.RoundConstsNew as New

--------------------------------------------------------------------------------

-- | Which set of round constants
data Flavour 
  = HorizenLabsOld
  | HorizenLabsNew
  deriving (Eq, Show)

--------------------------------------------------------------------------------

sbox :: Fr -> Fr
sbox !x = x4*x where
  x2 = x *x
  x4 = x2*x2

internalRound :: Fr -> (Fr,Fr,Fr) -> (Fr,Fr,Fr) 
internalRound !c (x,y,z) = 
  ( 2*x' +   y +   z 
  ,   x' + 2*y +   z 
  ,   x' +   y + 3*z 
  )
  where
    x' = sbox (x + c) 

externalRound :: (Fr,Fr,Fr) -> (Fr,Fr,Fr) -> (Fr,Fr,Fr)
externalRound !(cx,cy,cz) !(x,y,z) = (x'+s , y'+s , z'+s) where
  x' = sbox (x + cx)
  y' = sbox (y + cy)
  z' = sbox (z + cz)
  s  = x' + y' + z'

linearLayer :: (Fr,Fr,Fr) -> (Fr,Fr,Fr)
linearLayer !(x,y,z) = (x+s, y+s, z+s) where s = x+y+z

--------------------------------------------------------------------------------

permutationOld :: (Fr,Fr,Fr) -> (Fr,Fr,Fr)
permutationOld 
  = (\state -> foldl (flip externalRound) state Old.finalRoundConsts   )
  . (\state -> foldl (flip internalRound) state Old.internalRoundConsts)
  . (\state -> foldl (flip externalRound) state Old.initialRoundConsts )
  . linearLayer


permutationNew :: (Fr,Fr,Fr) -> (Fr,Fr,Fr)
permutationNew 
  = (\state -> foldl (flip externalRound) state New.finalRoundConsts   )
  . (\state -> foldl (flip internalRound) state New.internalRoundConsts)
  . (\state -> foldl (flip externalRound) state New.initialRoundConsts )
  . linearLayer

permutation :: Flavour -> (Fr,Fr,Fr) -> (Fr,Fr,Fr)
permutation HorizenLabsOld = permutationOld 
permutation HorizenLabsNew = permutationNew

--------------------------------------------------------------------------------

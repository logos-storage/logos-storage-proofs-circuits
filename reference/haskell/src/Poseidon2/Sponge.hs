
{-# LANGUAGE BangPatterns #-}
module Poseidon2.Sponge 
  ( Flavour(..)
  , sponge1
  , sponge2
  ) 
  where

--------------------------------------------------------------------------------

import ZK.Algebra.Curves.BN128.Fr.Mont (Fr)

import Poseidon2.Permutation

--------------------------------------------------------------------------------

-- | Sponge construction with rate=1 (capacity=2), zero IV and 10* padding
sponge1 :: Flavour -> [Fr] -> Fr
sponge1 !flavour input = go (0,0,civ) (pad input) where

  -- domain separation: capacity IV = 2^64 + 256*t + rate
  civ = fromInteger (2^64 + 0x0301)

  pad :: [Fr] -> [Fr]
  pad (x:xs) = x : pad xs
  pad []     = [1]

  go (sx,_ ,_ ) []     = sx
  go (sx,sy,sz) (a:as) = go state' as where 
    state' = permutation flavour (sx+a, sy, sz)

--------------------------------------------------------------------------------

-- | Sponge construction with rate=2 (capacity=1), zero IV and 10* padding
sponge2 :: Flavour -> [Fr] -> Fr
sponge2 !flavour input = go (0,0,civ) (pad input) where

  -- domain separation: capacity IV = 2^64 + 256*t + rate
  civ = fromInteger (2^64 + 0x0302)

  pad :: [Fr] -> [Fr]
  pad (x:y:rest) = x : y : pad rest
  pad [x]        = [x,1]
  pad []         = [1,0]

  go (sx,_ ,_ ) []         = sx
  go (sx,sy,sz) (a:b:rest) = go state' rest where 
    state' = permutation flavour (sx+a, sy+b, sz)

--------------------------------------------------------------------------------


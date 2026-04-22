
{-# LANGUAGE BangPatterns #-}
module Poseidon2.Sponge 
  ( Flavour(..)
  , SpongeRate(..)
  , InputFormat(..)
  , PaddingStrategy(..)
  , computeDomainSeparator
  , spongeFelts  , spongeBytes 
  , spongeFelts1 , spongeFelts2
  , sponge1' , sponge2'
  , byteStringToFieldElements
  ) 
  where

--------------------------------------------------------------------------------

import Data.Bits
import Data.ByteString (ByteString)
import qualified Data.ByteString as B

import ZK.Algebra.Curves.BN128.Fr.Mont (Fr)

import Poseidon2.Permutation

--------------------------------------------------------------------------------

data SpongeRate 
  = SpongeRate1
  | SpongeRate2
  deriving (Eq,Show)

data InputFormat
  = BitSequence         -- ^ sequence of bits
  | ByteSequence        -- ^ sequence of bytes
  | FeltSequenceBN254   -- ^ sequence of BN254 field elements
  deriving (Eq,Show)

data PaddingStrategy
  = NoPadding                   -- ^ no padding
  | Padding_Felts_10Star        -- ^ padding field elements with @10*@ (to a multiple of rate)
  | Padding_Bytes_10Star        -- ^ padding bytes with @10*@ (so that the result length is divisible by @(31*rate)@, eg. 62)
  | Padding_Felts_Bytes_10Star  -- ^ padding bytes with @10*@ to be divisible by 31, and then padding the resulting field element sequence too
  deriving (Eq,Show)

newtype DomSep = DomSep Fr

-- | domain separation: 
--
-- > capacity IV = 2^64 + 2^24*padding + 2^16*inputfmt + 256*t + rate
--
computeDomainSeparator :: SpongeRate -> InputFormat -> PaddingStrategy -> DomSep
computeDomainSeparator spongRate inputFormat paddingStrategy = DomSep (fromInteger domsep) where

  domsep :: Integer
  domsep = (2^64 + 2^24*padding + 2^16*inputfmt + 2^8*width + rate) 

  width :: Integer
  width = 3

  rate = case spongRate of 
    SpongeRate1 -> 1
    SpongeRate2 -> 2

  inputfmt = case inputFormat of
    BitSequence       -> 1
    ByteSequence      -> 8 
    FeltSequenceBN254 -> 254

  padding = case paddingStrategy of
    NoPadding                   -> 255
    Padding_Felts_10Star        -> 1
    Padding_Bytes_10Star        -> 16
    Padding_Felts_Bytes_10Star  -> 17

--------------------------------------------------------------------------------

spongeFelts :: SpongeRate -> Flavour -> [Fr] -> Fr
spongeFelts rate = case rate of
  SpongeRate1 -> spongeFelts1
  SpongeRate2 -> spongeFelts2

spongeBytes :: SpongeRate -> Flavour -> ByteString -> Fr
spongeBytes rate flavour bytes = case rate of
  SpongeRate1 -> sponge1' flavour (computeDomainSeparator rate ByteSequence Padding_Felts_Bytes_10Star) (byteStringToFieldElements bytes)
  SpongeRate2 -> sponge2' flavour (computeDomainSeparator rate ByteSequence Padding_Felts_Bytes_10Star) (byteStringToFieldElements bytes)

--------------------------------------------------------------------------------

-- | Sponge construction with rate=1 (capacity=2), and 10* padding
spongeFelts1 :: Flavour -> [Fr] -> Fr
spongeFelts1 flavour = sponge1' flavour (computeDomainSeparator SpongeRate1 FeltSequenceBN254 Padding_Felts_10Star)

sponge1' :: Flavour -> DomSep -> [Fr] -> Fr
sponge1' !flavour (DomSep civ) input = go (0,0,civ) (pad input) where

  pad :: [Fr] -> [Fr]
  pad (x:xs) = x : pad xs
  pad []     = [1]

  go (sx,_ ,_ ) []     = sx
  go (sx,sy,sz) (a:as) = go state' as where 
    state' = permutation flavour (sx+a, sy, sz)

--------------------------------------------------------------------------------

-- | Sponge construction with rate=2 (capacity=1), and 10* padding
spongeFelts2 :: Flavour -> [Fr] -> Fr
spongeFelts2 flavour = sponge2' flavour (computeDomainSeparator SpongeRate2 FeltSequenceBN254 Padding_Felts_10Star)

sponge2' :: Flavour -> DomSep -> [Fr] -> Fr
sponge2' !flavour (DomSep civ) input = go (0,0,civ) (pad input) where

  pad :: [Fr] -> [Fr]
  pad (x:y:rest) = x : y : pad rest
  pad [x]        = [x,1]
  pad []         = [1,0]

  go (sx,_ ,_ ) []         = sx
  go (sx,sy,sz) (a:b:rest) = go state' rest where 
    state' = permutation flavour (sx+a, sy+b, sz)

--------------------------------------------------------------------------------
-- * dealing with bytes

-- | A 31-byte long chunk
newtype Chunk 
  = Chunk ByteString 
  deriving Show

-- | Split bytestring into samller pieces, applying the @10*@ padding strategy.
--
-- That is, always add a single @0x01@ byte, and then add the necessary
-- number (in the interval @[0..k-1]@) of @0x00@ bytes to be a multiple of the 
-- given chunk length
--
padAndSplitByteString :: Int -> ByteString -> [Chunk]
padAndSplitByteString k orig = go (B.snoc orig 0x01) where
  go bs 
    | m == 0      = []
    | m < k       = [Chunk $ B.append bs (B.replicate (k-m) 0x00)]
    | otherwise   = (Chunk $ B.take k bs) : go (B.drop k bs)
    where
      m = B.length bs

-- | Chunk a ByteString into a sequence of field elements
byteStringToFieldElements :: ByteString -> [Fr]
byteStringToFieldElements rawdata = map chunkToField pieces where
  chunkSize = 31
  pieces = padAndSplitByteString chunkSize rawdata

chunkToField :: Chunk -> Fr
chunkToField chunk@(Chunk bs)
  | l == 31  = fromInteger (chunkToIntegerLE chunk)
  | l <  31  = error "chunkToField: chunk is too small (expecting exactly 31 bytes)"
  | l >  31  = error "chunkToField: chunk is too big (expecting exactly 31 bytes)"
  where 
    l = B.length bs

-- | Interpret a ByteString as an integer (little-endian)
chunkToIntegerLE :: Chunk -> Integer
chunkToIntegerLE (Chunk chunk) = go (B.unpack chunk) where
  go []     = 0
  go (w:ws) = fromIntegral w + shiftL (go ws) 8

--------------------------------------------------------------------------------


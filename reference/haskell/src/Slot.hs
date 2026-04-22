
{-# LANGUAGE BangPatterns, StrictData #-}
module Slot where

--------------------------------------------------------------------------------

import Data.Bits
import Data.Word
import Data.Array

import Data.ByteString (ByteString)
import qualified Data.ByteString       as B
import qualified Data.ByteString.Char8 as C

import Control.Monad
import System.IO

import Poseidon2
import Misc

--------------------------------------------------------------------------------

type Hash = Fr

newtype Seed     = Seed     Int deriving (Eq,Show)
newtype CellIdx  = CellIdx  Int deriving (Eq,Show)
newtype BlockIdx = BlockIdx Int deriving (Eq,Show)
newtype SlotIdx  = SlotIdx  Int deriving (Eq,Show)

newtype CellData  = CellData  { fromCellData  :: ByteString }
newtype BlockData = BlockData { fromBlockData :: ByteString }

instance Show CellData  where show (CellData  bs) = "CellData<"  ++ show (B.length bs) ++ ">"
instance Show BlockData where show (BlockData bs) = "BlockData<" ++ show (B.length bs) ++ ">"

mkCellData :: SlotConfig -> ByteString -> CellData
mkCellData cfg bs = if B.length bs == _cellSize cfg 
  then CellData bs
  else error $ "mkCellData: invalid cell size: " ++ show (B.length bs)

mkBlockData :: SlotConfig -> ByteString -> BlockData
mkBlockData cfg bs = if B.length bs == _blockSize cfg 
  then BlockData bs
  else error $ "mkBlockData: invalid block size: " ++ show (B.length bs)

data DataSource
  = SlotFile FilePath
  | FakeData Seed
  deriving Show

data SlotConfig = MkSlotCfg
  { _cellSize    :: Int           -- ^ cell size in bytes (eg. 2048)
  , _blockSize   :: Int           -- ^ block size in bytes (eg. 65536)
  , _nCells      :: Int           -- ^ number of cells per slot (should be power of two)
  , _nSamples    :: Int           -- ^ how many cells we sample
  , _hashFlavour :: Flavour       -- ^ which hash function instance to use
  , _dataSrc     :: DataSource    -- ^ slot data source
  }
  deriving Show

cellsPerBlock :: SlotConfig -> Int
cellsPerBlock cfg = case divMod (_blockSize cfg) (_cellSize cfg) of
  (q,0) -> if q>1 then q else error "cells per block must be at least 2"
  _     -> error "block size is not divisible by the cell size"

blocksPerSlot :: SlotConfig -> Int
blocksPerSlot cfg = case divMod (_nCells cfg) (cellsPerBlock cfg) of
  (q,0) -> if q>1 then q else error "blocks per slot must be at least 2"
  _     -> error "slot size is not divisible by the block size"


-- | Example slot configuration
exSlotCfg :: SlotConfig
exSlotCfg = MkSlotCfg
  { _cellSize    = 256
  , _blockSize   = 4096
  , _nCells      = 1024
  , _nSamples    = 20
  , _hashFlavour = HorizenLabsOld
  , _dataSrc     = FakeData (Seed 12345)
  }

fieldElemsPerCell :: SlotConfig -> Int
fieldElemsPerCell cfg = (_cellSize cfg + 30) `div` 31

--------------------------------------------------------------------------------
-- * load data

genFakeCell :: SlotConfig -> Seed -> CellIdx -> CellData
genFakeCell cfg (Seed seed) (CellIdx idx) = (mkCellData cfg $ B.pack list) where
  list = go (fromIntegral $ _cellSize cfg) 1 
  seed1 = fromIntegral seed + 0xdeadcafe :: Word64
  seed2 = fromIntegral idx  + 0x98765432 :: Word64
  go :: Word64 -> Word64 -> [Word8]
  go 0   _     = []
  go cnt state = fromIntegral state'' : go (cnt-1) state'' where
    state'  = state*(state + seed1)*(state + seed2) + state*(state `xor` 0x5a5a5a5a) + seed1*state + (seed2 + 17)
    state'' = mod state' 1698428844001831

genFakeBlock :: SlotConfig -> Seed -> BlockIdx -> BlockData
genFakeBlock cfg seed (BlockIdx blockIdx) = (mkBlockData cfg $ B.concat$ map fromCellData cells) where
  k = cellsPerBlock cfg
  a =  k *  blockIdx
  b =  k * (blockIdx + 1) - 1
  cells = [ genFakeCell cfg seed (CellIdx j) | j<-[a..b] ]

loadCellData :: SlotConfig -> CellIdx -> IO CellData
loadCellData cfg cellidx@(CellIdx idx) = case _dataSrc cfg of
  FakeData seed  -> return $ genFakeCell cfg seed cellidx
  SlotFile fname -> do
    h <- openBinaryFile fname ReadMode
    hSeek h AbsoluteSeek (fromIntegral (_cellSize cfg) * fromIntegral idx)
    bs <- B.hGet h (_cellSize cfg)
    hClose h
    return (mkCellData cfg bs)

loadBlockData :: SlotConfig -> BlockIdx -> IO BlockData
loadBlockData cfg blockidx@(BlockIdx idx) = case _dataSrc cfg of
  FakeData seed  -> return $ genFakeBlock cfg seed blockidx
  SlotFile fname -> do
    h <- openBinaryFile fname ReadMode
    hSeek h AbsoluteSeek (fromIntegral (_blockSize cfg) * fromIntegral idx)
    bs <- B.hGet h (_blockSize cfg)
    hClose h
    return (mkBlockData cfg bs)

--------------------------------------------------------------------------------

{-
calcSlotTree :: SlotConfig -> IO MerkleTree
calcSlotTree cfg = calcMerkleTree <$> calcCellHashes cfg

calcCellHashes :: SlotConfig -> IO [Hash]
calcCellHashes cfg = do
  forM [0..(_nCells cfg - 1)] $ \idx -> do
    cell <- loadCellData cfg idx 
    return (hashCell cell)
-}

--------------------------------------------------------------------------------

-- | Split bytestring into smaller pieces, no padding
splitByteString :: Int -> ByteString -> [ByteString]
splitByteString k = go where
  go bs 
    | B.null bs  = []
    | otherwise  = B.take k bs : go (B.drop k bs)

splitBlockToCells :: SlotConfig -> BlockData -> [CellData]
splitBlockToCells cfg (BlockData blockdata) = 
  map CellData (splitByteString (_cellSize cfg) blockdata)

calcBlockTree :: SlotConfig -> BlockIdx -> IO MerkleTree
calcBlockTree cfg idx = do
  block <- loadBlockData cfg idx
  let cells = splitBlockToCells cfg block
  let cellHashes = map (hashCell cfg) cells
  let tree = calcMerkleTree (_hashFlavour cfg) cellHashes
  return tree

calcAllBlockTrees :: SlotConfig -> IO (Array Int MerkleTree)
calcAllBlockTrees cfg 
  = listArray (0,n-1) <$> (forM [0..n-1] $ \idx -> calcBlockTree cfg (BlockIdx idx))
  where
    n = blocksPerSlot cfg

--------------------------------------------------------------------------------

data SlotTree = MkSlotTree
  { _miniTrees :: Array Int MerkleTree     -- ^ block trees
  , _bigTree   :: MerkleTree               -- ^ the tree over the block hashes
  }

slotTreeRoot :: SlotTree -> Hash
slotTreeRoot = merkleRootOf . _bigTree

calcSlotTree :: SlotConfig -> IO SlotTree
calcSlotTree cfg = do
  minitrees <- calcAllBlockTrees cfg
  let bigtree = calcMerkleTree (_hashFlavour cfg) $ map merkleRootOf $ elems minitrees
  return $ MkSlotTree minitrees bigtree

extractCellProof :: SlotConfig -> SlotTree -> CellIdx -> [Hash]
extractCellProof cfg slotTree (CellIdx cellIdx) = final where
  (blockIdx, withinBlockIdx) = cellIdx `divMod` (cellsPerBlock cfg)
  blockTree = (_miniTrees slotTree) ! blockIdx
  proof1 = extractMerkleProof blockTree           withinBlockIdx
  proof2 = extractMerkleProof (_bigTree slotTree) blockIdx
  final  = _merklePath proof1 ++ _merklePath proof2

checkCellProof :: SlotConfig -> SlotTree -> CellIdx -> Hash -> [Hash] -> Bool
checkCellProof cfg slotTree (CellIdx cellIdx) cellHash path 
  | logK + logM /= length path  = error "checkCellProof: incorrect Merkle path length"
  | 2^logK /= k                 = error "checkCellProof: non-power-of-two number of cells per blocks"
  | otherwise                   = reSlotHash == slotTreeRoot slotTree
  where
    k = cellsPerBlock cfg
    m = blocksPerSlot cfg
    logK = ceilingLog2 (fromIntegral k)
    logM = ceilingLog2 (fromIntegral m)

    blockIdx       = shiftR cellIdx logK
    inBlockCellIdx = cellIdx .&. (k-1)

    smallProof = MkMerkleProof
      { _flavour     = _hashFlavour cfg
      , _leafIndex   = inBlockCellIdx
      , _leafData    = cellHash
      , _merklePath  = take logK path
      , _dataSize    = k
      }
    bigProof = MkMerkleProof
      { _flavour     = _hashFlavour cfg
      , _leafIndex   = blockIdx
      , _leafData    = blockHash
      , _merklePath  = drop logK path
      , _dataSize    = m
      }

    blockHash  = reconstructMerkleRoot smallProof  
    reSlotHash = reconstructMerkleRoot bigProof

--------------------------------------------------------------------------------

-- | Hash a cell
hashCell :: SlotConfig -> CellData -> Hash
hashCell cfg (CellData rawdata) 
  | B.length rawdata /= _cellSize cfg  = error "hashCell: invalid cell data size"
  | otherwise                          = hashCell_ flavour rawdata
  where
    flavour = _hashFlavour cfg

hashCell_ :: Flavour -> ByteString -> Hash
hashCell_ flavour rawdata = sponge2 flavour (cellDataToFieldElements $ CellData rawdata) 

--------------------------------------------------------------------------------

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
cellDataToFieldElements :: CellData -> [Fr]
cellDataToFieldElements (CellData rawdata) = map chunkToField pieces where
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

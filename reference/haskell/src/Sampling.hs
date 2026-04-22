
{-# LANGUAGE BangPatterns, StrictData #-}
module Sampling where

--------------------------------------------------------------------------------

import Control.Monad
import System.IO

import qualified Data.ByteString as B

import Slot    as Slot
import DataSet as DataSet
import Poseidon2

import qualified ZK.Algebra.Curves.BN128.Fr.Mont as Fr

--------------------------------------------------------------------------------

samplingTest :: DataSetCfg -> SlotIdx -> Entropy -> FilePath -> IO ()
samplingTest dsetCfg slotIdx entropy fpath = do
  input <- calculateCircuitInput dsetCfg slotIdx entropy
  exportCircuitInput fpath input

--------------------------------------------------------------------------------

type Entropy = Fr

-- | Given an entropy source, the slot root, and a counter, we compute a
-- cell index to sample
sampleCellIndex :: SlotConfig -> Entropy -> Hash -> Int -> CellIdx
sampleCellIndex cfg entropy slotRoot counter = CellIdx (fromInteger idx) where
  u   = sponge2 (Slot._hashFlavour cfg) [entropy , slotRoot , fromIntegral counter] :: Fr
  idx = (Fr.from u) `mod` n          :: Integer
  n   = (fromIntegral $ Slot._nCells cfg) :: Integer
 
--------------------------------------------------------------------------------

padWithZeros :: Int -> [Fr] -> [Fr]
padWithZeros n xs 
  | m <= n     = xs ++ replicate (n-m) Fr.zero
  | otherwise  = error "padWithZeros: input too long"
  where
    m = length xs

--------------------------------------------------------------------------------

data CircuitInput = MkInput 
  { _entropy      :: Entropy       -- ^ public input
  , _dataSetRoot  :: Hash          -- ^ public input
  , _slotIndex    :: Int           -- ^ public input
  , _slotRoot     :: Hash          -- ^ private input
  , _slotProof    :: [Fr]          -- ^ private input
  , _slotsPerDSet :: Int           -- ^ private input
  , _cellsPerSlot :: Int           -- ^ private input
  , _cellData     :: [[Fr]]        -- ^ private input
  , _merklePaths  :: [[Fr]]        -- ^ private input
  }
  deriving Show

-- | Calculate the the inputs for the storage proof circuit
calculateCircuitInput :: DataSetCfg -> SlotIdx -> Entropy -> IO CircuitInput
calculateCircuitInput dataSetCfg slotIdx@(SlotIdx sidx) entropy = do
  let nslots = _nSlots dataSetCfg
  let flavour = DataSet._hashFlavour dataSetCfg

  let slotCfgs = [ dataSetSlotCfg dataSetCfg (SlotIdx i) | i <- [0..nslots-1] ]
  slotTrees <- mapM calcSlotTree slotCfgs 
  let !slotRoots = map slotTreeRoot slotTrees
  let !dsetTree  = calcMerkleTree flavour slotRoots
  let !dsetRoot  = merkleRootOf   dsetTree 

  let ourSlotCfg  = slotCfgs  !! sidx
  let ourSlotRoot = slotRoots !! sidx
  let ourSlotTree = slotTrees !! sidx
  let !idxs = [ sampleCellIndex ourSlotCfg entropy ourSlotRoot j | j <- [1..(Slot._nSamples ourSlotCfg)] ]

  cellData <- forM idxs $ \idx -> (cellDataToFieldElements <$> loadCellData ourSlotCfg idx)
  let !merklePaths = [ extractCellProof ourSlotCfg ourSlotTree idx | idx <- idxs ]
  return $ MkInput
    { _entropy      = entropy
    , _dataSetRoot  = dsetRoot
    , _slotIndex    = sidx
    , _slotRoot     = ourSlotRoot
    , _slotProof    = padWithZeros (_maxLog2NSlots dataSetCfg) $ extractMerkleProof_ dsetTree sidx
    , _slotsPerDSet = nslots
    , _cellsPerSlot = Slot._nCells ourSlotCfg
    , _cellData     = cellData
    , _merklePaths  = map (padWithZeros (_maxDepth dataSetCfg)) merklePaths
    }

-- | Export the inputs of the storage proof circuits in JSON format,
-- which @circom@ can consume.
--
-- NOTE: large numbers (field elements) must be encoded as JSON strings,
-- not numbers, as Javascript cannot handle large numbers!
--
exportCircuitInput :: FilePath -> CircuitInput -> IO ()
exportCircuitInput fpath input = do
  h <- openFile fpath WriteMode
  hPutStrLn h $ "{ \"entropy\":          " ++ show (show (_entropy      input))
  hPutStrLn h $ ", \"dataSetRoot\":      " ++ show (show (_dataSetRoot  input))
  hPutStrLn h $ ", \"slotIndex\":        " ++ show (show (_slotIndex    input))
  hPutStrLn h $ ", \"slotRoot\":         " ++ show (show (_slotRoot     input))
  hPutStrLn h $ ", \"nSlotsPerDataSet\": " ++ show (show (_slotsPerDSet input))
  hPutStrLn h $ ", \"nCellsPerSlot\":    " ++ show (show (_cellsPerSlot input))
  hPutStrLn h $ ", \"slotProof\":"
  hPrintList h 4 (map show $ _slotProof input)
  hPutStrLn h $ ", \"cellData\":" 
  hPrintListOfLists h ((map.map) show $ _cellData input)
  hPutStrLn h $ ", \"merklePaths\": " 
  hPrintListOfLists h ((map.map) show $ _merklePaths input)
  hPutStrLn h $ "}"
  hClose h

--------------------------------------------------------------------------------

trueFalses :: [Bool]
trueFalses = True : repeat False

indent :: Int -> String
indent k = replicate k ' '

hPrintList' :: Show a => Handle -> (Bool -> String) -> [a] -> IO ()
hPrintList' h indentation xs = do
  forM_ (zip trueFalses xs) $ \(b,x) -> do
    hPutStrLn h (indentation b ++ (if b then "[ " else ", ") ++ show x)
  hPutStrLn h (indentation False ++ "]")

hPrintList :: Show a => Handle -> Int -> [a] -> IO ()
hPrintList h indentBy xs = hPrintList' h (\_ -> indent indentBy) $ xs

hPrintListOfLists :: Show a => Handle -> [[a]] -> IO ()
hPrintListOfLists h xss = 
  do
    forM_ (zip trueFalses xss) $ \(b,xs) -> hPrintList' h (myIndentation b) xs
    hPutStrLn h ("    ]")
  where
    myIndentation True  True  = "    [ "
    myIndentation False True  = "    , "
    myIndentation _     False = "      "

--------------------------------------------------------------------------------

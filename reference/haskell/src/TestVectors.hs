
-- | Generate test vectors to compare with other implementations

module TestVectors where

--------------------------------------------------------------------------------

import Control.Monad

import Data.Word
import Data.ByteString (ByteString)
import qualified Data.ByteString as B

import Poseidon2.Merkle
import Poseidon2.Sponge
import Slot

import ZK.Algebra.Curves.BN128.Fr.Mont (Fr)

--------------------------------------------------------------------------------

allTestVectors :: IO ()
allTestVectors = do
  putStrLn "\nTEST VECTORS FOR *OLD* ROUND CONSTANTS"
  putStrLn "======================================"
  allTestVectors' HorizenLabsOld
  putStrLn "\nTEST VECTORS FOR *NEW* ROUND CONSTANTS"
  putStrLn "======================================"
  allTestVectors' HorizenLabsNew

allTestVectors' :: Flavour -> IO ()
allTestVectors' flavour = do
  testVectorsSponge       flavour 
  testVectorsHash         flavour
  testVectorsMerkleAsHash flavour
  testVectorsMerkleFull   flavour

--------------------------------------------------------------------------------

showFelt :: Fr -> String
showFelt x 
  | n0 > 77   = error "showFelt: should not happen"
  | otherwise = replicate (77-n0) '0' ++ s0
  where
    s0 = show x
    n0 = length s0

--------------------------------------------------------------------------------

testVectorsSponge :: Flavour -> IO ()
testVectorsSponge flavour = do
  putStrLn ""
  putStrLn $ "test vectors for sponge of field elements with rate=1 | " ++ show flavour
  putStrLn "-------------------------------------------------------------------"
  forM_ [0..8] $ \n -> do
    let input = map fromIntegral [1..n] :: [Fr]
    putStrLn $ "hash of [1.." ++ show n ++ "] :: [Fr] =  " ++ showFelt (spongeFelts SpongeRate1 flavour input)

  putStrLn ""
  putStrLn $ "test vectors for sponge of field elements with rate=2 | " ++ show flavour
  putStrLn "-------------------------------------------------------------------"
  forM_ [0..8] $ \n -> do
    let input = map fromIntegral [1..n] :: [Fr]
    putStrLn $ "hash of [1.." ++ show n ++ "] :: [Fr] =  " ++ showFelt (spongeFelts SpongeRate2 flavour input)

--------------------------------------------------------------------------------

testVectorsHash :: Flavour -> IO ()
testVectorsHash flavour = do

  putStrLn ""
  putStrLn $ "test vectors for hash (padded sponge with rate=2) of bytes | " ++ show flavour
  putStrLn "----------------------------------------------------------"
  forM_ [0..80] $ \n -> do
    let input = map fromIntegral [1..n] :: [Word8]
    let bs    = B.pack input
    putStrLn $ "hash of [1.." ++ show n ++ "] :: [Byte] =  " ++ showFelt (spongeBytes SpongeRate2 flavour bs)

--------------------------------------------------------------------------------

testVectorsMerkleAsHash :: Flavour -> IO ()
testVectorsMerkleAsHash flavour = do
  putStrLn ""
  putStrLn $ "test vectors for Merkle roots (used as a hash function) of sequences of field elements | " ++ show flavour
  putStrLn "-----------------------------------------------"
  forM_ [1..40] $ \n -> do
    let input = map fromIntegral [1..n] :: [Fr]
    let root  =                calcMerkleRoot flavour input
    let root' = merkleRootOf $ calcMerkleTree flavour input
    if root == root'
      then putStrLn $ "Merkle root of [1.." ++ show n ++ "] :: [Fr]  =  " ++ showFelt root
      else fail "testVectorsMerkleAsHash: FATAL"

  putStrLn ""
  putStrLn $ "test vectors for Merkle roots (used as a hash function) of sequence of bytes | " ++ show flavour
  putStrLn "--------------------------------------------------"
  forM_ [0..80] $ \n -> do
    let input = map fromIntegral [1..n] :: [Word8]
    let bs    = B.pack input
    let flds  = byteStringToFieldElements bs

    let root  =                calcMerkleRoot flavour flds
    let root' = merkleRootOf $ calcMerkleTree flavour flds
    if root == root'
      then putStrLn $ "Merkle root of [1.." ++ show n ++ "] :: [Byte]  =  " ++ showFelt root
      else fail "testVectorsMerkleAsHash: FATAL"
    
--------------------------------------------------------------------------------

testVectorsMerkleFull :: Flavour -> IO ()
testVectorsMerkleFull flavour = do
  putStrLn ""
  putStrLn $ "test vectors for Merkle roots, where the leaves are sequences of bytes | " ++ show flavour
  putStrLn "--------------------------------------------------"
  forM_ [1..81] $ \n -> do
    let inputs = makeInputs n
    putStrLn $ "Merkle root of [ [0..j-1] | j<-[1.." ++ show n ++ "] :: [[Byte]]  =  " ++ showFelt (merkleRootOf $ calcMerkleTreeByteStrings flavour inputs)
  where
    makeInput :: Int -> Int -> ByteString
    makeInput n j = B.pack $ map (fromIntegral :: Int -> Word8) [0..j-1]

    makeInputs :: Int -> [ByteString]
    makeInputs n = [ makeInput n j | j<-[1..n] ]

--------------------------------------------------------------------------------

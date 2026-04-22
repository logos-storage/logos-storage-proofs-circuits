
-- | Generate test vectors to compare with other implementations

module TestVectors where

--------------------------------------------------------------------------------

import Control.Monad

import Data.Word
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
  testVectorsSponge flavour 
  testVectorsHash   flavour
  testVectorsMerkle flavour

--------------------------------------------------------------------------------

testVectorsSponge :: Flavour -> IO ()
testVectorsSponge flavour = do
  putStrLn ""
  putStrLn $ "test vectors for sponge of field elements with rate=1 | " ++ show flavour
  putStrLn "-------------------------------------------------------------------"
  forM_ [0..8] $ \n -> do
    let input = map fromIntegral [1..n] :: [Fr]
    putStrLn $ "hash of [1.." ++ show n ++ "] :: [Fr] =  " ++ show (sponge1 flavour input)

  putStrLn ""
  putStrLn $ "test vectors for sponge of field elements with rate=2 | " ++ show flavour
  putStrLn "-------------------------------------------------------------------"
  forM_ [0..8] $ \n -> do
    let input = map fromIntegral [1..n] :: [Fr]
    putStrLn $ "hash of [1.." ++ show n ++ "] :: [Fr] =  " ++ show (sponge2 flavour input)

--------------------------------------------------------------------------------

testVectorsHash :: Flavour -> IO ()
testVectorsHash flavour = do

  putStrLn ""
  putStrLn $ "test vectors for hash (padded sponge with rate=2) of bytes | " ++ show flavour
  putStrLn "----------------------------------------------------------"
  forM_ [0..80] $ \n -> do
    let input = map fromIntegral [1..n] :: [Word8]
    let bs    = B.pack input
    putStrLn $ "hash of [1.." ++ show n ++ "] :: [Byte] =  " ++ show (hashCell_ flavour bs)

--------------------------------------------------------------------------------

testVectorsMerkle :: Flavour -> IO ()
testVectorsMerkle flavour = do
  putStrLn ""
  putStrLn $ "test vectors for Merkle roots of field elements | " ++ show flavour
  putStrLn "-----------------------------------------------"
  forM_ [1..40] $ \n -> do
    let input = map fromIntegral [1..n] :: [Fr]
    putStrLn $ "Merkle root of [1.." ++ show n ++ "] :: [Fr]  =  " ++ show (calcMerkleRoot flavour input)

  putStrLn ""
  putStrLn $ "test vectors for Merkle roots of sequence of bytes | " ++ show flavour
  putStrLn "--------------------------------------------------"
  forM_ [0..80] $ \n -> do
    let input = map fromIntegral [1..n] :: [Word8]
    let bs    = B.pack input
    let flds  = cellDataToFieldElements (CellData bs)
    putStrLn $ "Merkle root of [1.." ++ show n ++ "] :: [Byte]  =  " ++ show (calcMerkleRoot flavour flds)

--------------------------------------------------------------------------------

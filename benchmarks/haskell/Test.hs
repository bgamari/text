{-# LANGUAGE BangPatterns #-}

module Main where

import Criterion.Main
import qualified Data.Text as T


main :: IO ()
main = do
  let !ta = T.replicate 1000 $ T.pack "a"
      !tb = T.toUpper ta
  defaultMain
    [ bench "test" $ nf (T.cons 'a') ta
    ]

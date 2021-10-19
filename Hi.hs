{-# LANGUAGE OverloadedStrings #-}

import qualified Data.ByteString
import qualified Data.Text
import qualified Data.Text.Encoding

f :: Data.ByteString.ByteString -> Data.Text.Text
f = Data.Text.Encoding.decodeUtf16LE 
{-# NOINLINE f #-}

main = do
    let x = "\0\216"
    print $ f x

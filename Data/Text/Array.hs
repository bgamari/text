{-# LANGUAGE BangPatterns, CPP, MagicHash, Rank2Types, RecordWildCards,
    UnboxedTuples #-}
{-# OPTIONS_GHC -fno-warn-unused-matches #-}
-- |
-- Module      : Data.Text.Array
-- Copyright   : (c) 2009, 2010 Bryan O'Sullivan
--
-- License     : BSD-style
-- Maintainer  : bos@serpentine.com, rtomharper@googlemail.com,
--               duncan@haskell.org
-- Stability   : experimental
-- Portability : portable
--
-- Packed, unboxed, heap-resident arrays.  Suitable for performance
-- critical use, both in terms of large data quantities and high
-- speed.
--
-- This module is intended to be imported @qualified@, to avoid name
-- clashes with "Prelude" functions, e.g.
--
-- > import qualified Data.Text.Array as A
--
-- The names in this module resemble those in the 'Data.Array' family
-- of modules, but are shorter due to the assumption of qualifid
-- naming.
module Data.Text.Array
    (
    -- * Types
      Array
    , MArray

    -- * Functions
    , copy
    , partialCopyM
    , partialCopyI
    , empty
    , run
    , run2
    , toList
    , unsafeFreeze
    , unsafeIndex
    , unsafeNew
    , unsafeWrite
    ) where

#if defined(ASSERTS)
-- This fugly hack is brought by GHC's apparent reluctance to deal
-- with MagicHash and UnboxedTuples when inferring types. Eek!
# define CHECK_BOUNDS(_func_,_len_,_k_) \
if (_k_) < 0 || (_k_) >= (_len_) then error ("Data.Text.Array." ++ (_func_) ++ ": bounds error, offset " ++ show (_k_) ++ ", length " ++ show (_len_)) else
#else
# define CHECK_BOUNDS(_func_,_len_,_k_)
#endif

#include "MachDeps.h"

#if defined(ASSERTS)
import Control.Exception (assert)
#endif
import Data.Bits ((.&.))
import Data.Text.UnsafeShift (shiftL, shiftR)
import GHC.Base (ByteArray#, MutableByteArray#, Int(..),
                 indexWord16Array#, indexWordArray#, newByteArray#,
                 readWord16Array#, readWordArray#, unsafeCoerce#,
                 writeWord16Array#, writeWordArray#)
import GHC.ST (ST(..), runST)
import GHC.Word (Word16(..), Word(..))
import Prelude hiding (length, read)

-- | Immutable array type.
data Array = Array {
      aBA :: ByteArray#
    , aLen :: {-# UNPACK #-} !Int -- length (in units of Word16, not bytes)
    }

-- | Mutable array type, for use in the ST monad.
data MArray s = MArray {
      maBA :: MutableByteArray# s
    , maLen :: {-# UNPACK #-} !Int -- length (in units of Word16, not bytes)
    }

-- | Operations supported by all arrays.
class IArray a where
    -- | Return the length of an array.
    length :: a -> Int

instance IArray Array where
    length = aLen
    {-# INLINE length #-}

instance IArray (MArray s) where
    length = maLen
    {-# INLINE length #-}

-- | Create an uninitialized mutable array.
unsafeNew :: forall s. Int -> ST s (MArray s)
unsafeNew n =
#if defined(ASSERTS)
    assert (n >= 0) .
#endif
    ST $ \s1# ->
    case bytesInArray n of
      len@(I# len#) ->
#if defined(ASSERTS)
         if len < 0 then error (show ("unsafeNew",len)) else
#endif
         case newByteArray# len# s1# of
           (# s2#, marr# #) -> (# s2#, MArray marr# n #)
{-# INLINE unsafeNew #-}

-- | Freeze a mutable array. Do not mutate the 'MArray' afterwards!
unsafeFreeze :: MArray s -> ST s Array
unsafeFreeze MArray{..} = ST $ \s# ->
                          (# s#, Array (unsafeCoerce# maBA) maLen #)
{-# INLINE unsafeFreeze #-}

-- | Indicate how many bytes would be used for an array of the given
-- size.
bytesInArray :: Int -> Int
bytesInArray n = n `shiftL` 1
{-# INLINE bytesInArray #-}

-- | Unchecked read of an immutable array.  May return garbage or
-- crash on an out-of-bounds access.
unsafeIndex :: Array -> Int -> Word16
unsafeIndex Array{..} i@(I# i#) =
  CHECK_BOUNDS("unsafeIndex",len,i)
    case indexWord16Array# aBA i# of r# -> (W16# r#)
{-# INLINE unsafeIndex #-}

-- | Unchecked read of an immutable array.  May return garbage or
-- crash on an out-of-bounds access.
unsafeIndexWord :: Array -> Int -> Word
unsafeIndexWord Array{..} i@(I# i#) =
  CHECK_BOUNDS("unsafeIndexWord",len,i)
    case indexWordArray# aBA i# of r# -> (W# r#)
{-# INLINE unsafeIndexWord #-}

-- | Unchecked read of a mutable array.  May return garbage or
-- crash on an out-of-bounds access.
unsafeRead :: MArray s -> Int -> ST s Word16
unsafeRead MArray{..} i@(I# i#) = ST $ \s# ->
  CHECK_BOUNDS("unsafeRead",len,i)
  case readWord16Array# maBA i# s# of
    (# s2#, r# #) -> (# s2#, W16# r# #)
{-# INLINE unsafeRead #-}

-- | Unchecked write of a mutable array.  May return garbage or crash
-- on an out-of-bounds access.
unsafeWrite :: MArray s -> Int -> Word16 -> ST s ()
unsafeWrite MArray{..} i@(I# i#) (W16# e#) = ST $ \s1# ->
  CHECK_BOUNDS("unsafeWrite",len,i)
  case writeWord16Array# maBA i# e# s1# of
    s2# -> (# s2#, () #)
{-# INLINE unsafeWrite #-}

-- | Unchecked read of a mutable array.  May return garbage or
-- crash on an out-of-bounds access.
unsafeReadWord :: MArray s -> Int -> ST s Word
unsafeReadWord MArray{..} i@(I# i#) = ST $ \s# ->
  CHECK_BOUNDS("unsafeRead64",len,i)
  case readWordArray# maBA i# s# of
    (# s2#, r# #) -> (# s2#, W# r# #)
{-# INLINE unsafeReadWord #-}

-- | Unchecked write of a mutable array.  May return garbage or crash
-- on an out-of-bounds access.
unsafeWriteWord :: MArray s -> Int -> Word -> ST s ()
unsafeWriteWord MArray{..} i@(I# i#) (W# e#) = ST $ \s1# ->
  CHECK_BOUNDS("unsafeWriteWord",len,i)
  case writeWordArray# maBA i# e# s1# of
    s2# -> (# s2#, () #)
{-# INLINE unsafeWriteWord #-}

-- | Convert an immutable array to a list.
toList :: Array -> [Word16]
toList a = loop 0
    where loop i | i < len   = unsafeIndex a i : loop (i+1)
                 | otherwise = []
          len = length a

-- | An empty immutable array.
empty :: Array
empty = runST (unsafeNew 0 >>= unsafeFreeze)

-- | Run an action in the ST monad and return an immutable array of
-- its result.
run :: (forall s. ST s (MArray s)) -> Array
run k = runST (k >>= unsafeFreeze)

-- | Run an action in the ST monad and return an immutable array of
-- its result paired with whatever else the action returns.
run2 :: (forall s. ST s (MArray s, a)) -> (Array, a)
run2 k = runST (do
                 (marr,b) <- k
                 arr <- unsafeFreeze marr
                 return (arr,b))

-- | The amount to divide or multiply by to switch between units of
-- 'Word16' and units of 'Word'.
wordFactor :: Int
wordFactor = SIZEOF_HSWORD `shiftR` 1

-- | Indicate whether an offset is word-aligned.
wordAligned :: Int -> Bool
wordAligned i = i .&. (wordFactor - 1) == 0

-- | Copy an array in its entirety. The destination array must be at
-- least as big as the source.
copy :: MArray s     -- ^ source array
     -> MArray s     -- ^ destination array
     -> ST s ()
copy dest@(MArray _ dlen) src@(MArray _ slen)
    | dlen >= slen = fast_loop 0
    | otherwise    = fail "Data.Text.Array.copy: array too small"
    where
      nwds = slen `div` wordFactor
      fast_loop !i
          | i >= nwds = copy_loop (i * wordFactor)
          | otherwise = do unsafeReadWord src i >>= unsafeWriteWord dest i
                           fast_loop (i+1)
      copy_loop !i
          | i >= slen = return ()
          | otherwise = do unsafeRead src i >>= unsafeWrite dest i
                           copy_loop (i+1)

-- | Copy some elements of a mutable array.
partialCopyM :: MArray s        -- ^ Destination
             -> Int             -- ^ Destination offset
             -> MArray s        -- ^ Source
             -> Int             -- ^ Source offset
             -> Int             -- ^ Count
             -> ST s ()
partialCopyM dest didx src sidx count =
#if defined(ASSERTS)
    assert (sidx + count <= length src) .
    assert (didx + count <= length dest) $
#endif
    copy_loop sidx didx 0
    where
      copy_loop !i !j !c
          | c >= count  = return ()
          | otherwise = do unsafeRead src i >>= unsafeWrite dest j
                           copy_loop (i+1) (j+1) (c+1)

-- | Copy some elements of an immutable array.
partialCopyI :: MArray s        -- ^ Destination
             -> Int             -- ^ Destination offset
             -> Array           -- ^ Source
             -> Int             -- ^ Source offset
             -> Int             -- ^ First offset in source /not/ to
                                -- copy (i.e. /not/ length)
             -> ST s ()
partialCopyI dest i0 src j0 top
    | wordAligned i0 && wordAligned j0 = fast (i0 `div` wordFactor) (j0 `div` wordFactor)
    | otherwise = slow i0 j0
  where
    topwds = top `div` wordFactor
    fast !i !j
        | i >= topwds = slow (i * wordFactor) (j * wordFactor)
        | otherwise   = do unsafeWriteWord dest i (src `unsafeIndexWord` j)
                           fast (i+1) (j+1)
    slow !i !j
        | i >= top  = return ()
        | otherwise = do unsafeWrite dest i (src `unsafeIndex` j)
                         slow (i+1) (j+1)

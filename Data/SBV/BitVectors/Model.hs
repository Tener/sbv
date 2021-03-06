-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.BitVectors.Model
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Instance declarations for our symbolic world
-----------------------------------------------------------------------------

{-# OPTIONS_GHC -fno-warn-orphans   #-}
{-# LANGUAGE TypeSynonymInstances   #-}
{-# LANGUAGE PatternGuards          #-}
{-# LANGUAGE FlexibleInstances      #-}
{-# LANGUAGE MultiParamTypeClasses  #-}
{-# LANGUAGE ScopedTypeVariables    #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE Rank2Types             #-}

module Data.SBV.BitVectors.Model (
    Mergeable(..), EqSymbolic(..), OrdSymbolic(..), BVDivisible(..), Uninterpreted(..)
  , bitValue, setBitTo, allEqual, allDifferent, oneIf, blastBE, blastLE
  , lsb, msb, SBVUF, sbvUFName, genFinVar, genFinVar_, forall, forall_, exists, exists_
  )
  where

import Control.Monad   (when)

import Data.Array      (Array, Ix, listArray, elems, bounds, rangeSize)
import Data.Bits       (Bits(..))
import Data.Int        (Int8, Int16, Int32, Int64)
import Data.List       (genericLength, genericIndex, genericSplitAt, unzip4, unzip5, unzip6, unzip7, intercalate)
import Data.Word       (Word8, Word16, Word32, Word64)

import Test.QuickCheck                           (Testable(..), Arbitrary(..))
import qualified Test.QuickCheck         as QC   (whenFail)
import qualified Test.QuickCheck.Monadic as QC   (monadicIO, run)
import System.Random

import Data.SBV.BitVectors.Data
import Data.SBV.Utils.Boolean

liftSym1 :: (State -> (Bool, Size) -> SW -> IO SW) ->
            (Integer -> Integer) -> SBV b -> SBV b
liftSym1 _   opC (SBV sgnsz (Left a))  = SBV sgnsz $ Left  $ mapCW opC a
liftSym1 opS _   a@(SBV sgnsz _)       = SBV sgnsz $ Right $ cache c
   where c st = do swa <- sbvToSW st a
                   opS st sgnsz swa

liftSym2 :: (State -> (Bool, Size) -> SW -> SW -> IO SW) ->
            (Integer -> Integer -> Integer) -> SBV b -> SBV b -> SBV b
liftSym2 _   opC (SBV sgnsz (Left a)) (SBV _ (Left b)) = SBV sgnsz $ Left  $ mapCW2 opC a b
liftSym2 opS _   a@(SBV sgnsz _)      b                = SBV sgnsz $ Right $ cache c
  where c st = do sw1 <- sbvToSW st a
                  sw2 <- sbvToSW st b
                  opS st sgnsz sw1 sw2

liftSym2B :: (State -> (Bool, Size) -> SW -> SW -> IO SW)
          -> (Integer -> Integer -> Bool)
          -> SBV b -> SBV b -> SBool
liftSym2B _   opC (SBV _ (Left a)) (SBV _ (Left b)) = literal (liftCW2 opC a b)
liftSym2B opS _   a                b                = SBV (False, Size (Just 1)) $ Right $ cache c
  where c st = do sw1 <- sbvToSW st a
                  sw2 <- sbvToSW st b
                  opS st (False, Size (Just 1)) sw1 sw2

liftSym1Bool :: (State -> (Bool, Size) -> SW -> IO SW)
             -> (Bool -> Bool)
             -> SBool -> SBool
liftSym1Bool _   opC (SBV _ (Left a)) = literal $ opC $ cwToBool a
liftSym1Bool opS _   a                = SBV (False, Size (Just 1)) $ Right $ cache c
  where c st = do sw <- sbvToSW st a
                  opS st (False, Size (Just 1)) sw

liftSym2Bool :: (State -> (Bool, Size) -> SW -> SW -> IO SW)
             -> (Bool -> Bool -> Bool)
             -> SBool -> SBool -> SBool
liftSym2Bool _   opC (SBV _ (Left a)) (SBV _ (Left b)) = literal (cwToBool a `opC` cwToBool b)
liftSym2Bool opS _   a                b                = SBV (False, Size (Just 1)) $ Right $ cache c
  where c st = do sw1 <- sbvToSW st a
                  sw2 <- sbvToSW st b
                  opS st (False, Size (Just 1)) sw1 sw2

mkSymOpSC :: (SW -> SW -> Maybe SW) -> Op -> State -> (Bool, Size) -> SW -> SW -> IO SW
mkSymOpSC shortCut op st sgnsz a b = maybe (newExpr st sgnsz (SBVApp op [a, b])) return (shortCut a b)

mkSymOp :: Op -> State -> (Bool, Size) -> SW -> SW -> IO SW
mkSymOp = mkSymOpSC (const (const Nothing))

mkSymOp1SC :: (SW -> Maybe SW) -> Op -> State -> (Bool, Size) -> SW -> IO SW
mkSymOp1SC shortCut op st sgnsz a = maybe (newExpr st sgnsz (SBVApp op [a])) return (shortCut a)

mkSymOp1 :: Op -> State -> (Bool, Size) -> SW -> IO SW
mkSymOp1 = mkSymOp1SC (const Nothing)

-- Symbolic-Word class instances

genFinVar :: (Random a, SymWord a) => Quantifier -> (Bool, Int) -> String -> Symbolic (SBV a)
genFinVar q (sg, sz) = mkSymSBV q (sg, Size (Just sz)) . Just

genFinVar_ :: (Random a, SymWord a) => Quantifier -> (Bool, Int) -> Symbolic (SBV a)
genFinVar_ q (sg, sz) = mkSymSBV q (sg, Size (Just sz)) Nothing

genFinLiteral :: Integral a => (Bool, Int) -> a -> SBV b
genFinLiteral (sg, sz)  = SBV s . Left . mkConstCW s
  where s = (sg, Size (Just sz))

genFromCW :: Integral a => CW -> a
genFromCW x = fromInteger (cwVal x)

instance SymWord Bool where
  forall     = genFinVar  ALL (False, 1)
  forall_    = genFinVar_ ALL (False, 1)
  exists     = genFinVar  EX  (False, 1)
  exists_    = genFinVar_ EX  (False, 1)
  literal x  = genFinLiteral (False, 1) (if x then (1::Integer) else 0)
  fromCW     = cwToBool
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Word8 where
  forall     = genFinVar   ALL (False, 8)
  forall_    = genFinVar_  ALL (False, 8)
  exists     = genFinVar   EX  (False, 8)
  exists_    = genFinVar_  EX  (False, 8)
  literal    = genFinLiteral (False, 8)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Int8 where
  forall     = genFinVar   ALL (True, 8)
  forall_    = genFinVar_  ALL (True, 8)
  exists     = genFinVar   EX  (True, 8)
  exists_    = genFinVar_  EX  (True, 8)
  literal    = genFinLiteral (True, 8)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Word16 where
  forall     = genFinVar   ALL (False, 16)
  forall_    = genFinVar_  ALL (False, 16)
  exists     = genFinVar   EX  (False, 16)
  exists_    = genFinVar_  EX  (False, 16)
  literal    = genFinLiteral (False, 16)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Int16 where
  forall     = genFinVar   ALL (True, 16)
  forall_    = genFinVar_  ALL (True, 16)
  exists     = genFinVar   EX  (True, 16)
  exists_    = genFinVar_  EX  (True, 16)
  literal    = genFinLiteral (True, 16)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Word32 where
  forall     = genFinVar   ALL (False, 32)
  forall_    = genFinVar_  ALL (False, 32)
  exists     = genFinVar   EX  (False, 32)
  exists_    = genFinVar_  EX  (False, 32)
  literal    = genFinLiteral (False, 32)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Int32 where
  forall     = genFinVar   ALL (True, 32)
  forall_    = genFinVar_  ALL (True, 32)
  exists     = genFinVar   EX  (True, 32)
  exists_    = genFinVar_  EX  (True, 32)
  literal    = genFinLiteral (True, 32)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Word64 where
  forall     = genFinVar   ALL (False, 64)
  forall_    = genFinVar_  ALL (False, 64)
  exists     = genFinVar   EX  (False, 64)
  exists_    = genFinVar_  EX  (False, 64)
  literal    = genFinLiteral (False, 64)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Int64 where
  forall     = genFinVar   ALL (True, 64)
  forall_    = genFinVar_  ALL (True, 64)
  exists     = genFinVar   EX  (True, 64)
  exists_    = genFinVar_  EX  (True, 64)
  literal    = genFinLiteral (True, 64)
  fromCW     = genFromCW
  mbMaxBound = Just maxBound
  mbMinBound = Just minBound

instance SymWord Integer where
  forall     = mkSymSBV ALL (True, Size Nothing) . Just
  forall_    = mkSymSBV ALL (True, Size Nothing) Nothing
  exists     = mkSymSBV EX  (True, Size Nothing) . Just
  exists_    = mkSymSBV EX  (True, Size Nothing) Nothing
  literal    = SBV (True, Size Nothing) . Left . mkConstCW (True, Size Nothing)
  fromCW     = genFromCW
  mbMaxBound = Nothing
  mbMinBound = Nothing

-- | Symbolic Equality. Note that we can't use Haskell's 'Eq' class since Haskell insists on returning Bool
-- Comparing symbolic values will necessarily return a symbolic value.
--
-- Minimal complete definition: '.=='
infix 4 .==, ./=
class EqSymbolic a where
  (.==), (./=) :: a -> a -> SBool
  -- minimal complete definition: .==
  x ./= y = bnot (x .== y)

-- | Symbolic Comparisons. Similar to 'Eq', we cannot implement Haskell's 'Ord' class
-- since there is no way to return an 'Ordering' value from a symbolic comparison.
-- Furthermore, 'OrdSymbolic' requires 'Mergeable' to implement if-then-else, for the
-- benefit of implementing symbolic versions of 'max' and 'min' functions.
--
-- Minimal complete definition: '.<'
infix 4 .<, .<=, .>, .>=
class (Mergeable a, EqSymbolic a) => OrdSymbolic a where
  (.<), (.<=), (.>), (.>=) :: a -> a -> SBool
  smin, smax :: a -> a -> a
  -- minimal complete definition: .<
  a .<= b    = a .< b ||| a .== b
  a .>  b    = b .<  a
  a .>= b    = b .<= a
  a `smin` b = ite (a .<= b) a b
  a `smax` b = ite (a .<= b) b a

{- We can't have a generic instance of the form:

instance Eq a => EqSymbolic a where
  x .== y = if x == y then true else false

even if we're willing to allow Flexible/undecidable instances..
This is because if we allow this it would imply EqSymbolic (SBV a);
since (SBV a) has to be Eq as it must be a Num. But this wouldn't be
the right choice obviously; as the Eq instance is bogus for SBV
for natural reasons..
-}

instance EqSymbolic (SBV a) where
  (.==) = liftSym2B (mkSymOpSC (eqOpt trueSW) Equal)    (==)
  (./=) = liftSym2B (mkSymOpSC (eqOpt falseSW) NotEqual) (/=)

eqOpt :: SW -> SW -> SW -> Maybe SW
eqOpt w x y = if x == y then Just w else Nothing

instance SymWord a => OrdSymbolic (SBV a) where
  x .< y
    | Just mb <- mbMaxBound, x `isConcretely` (== mb) = false
    | Just mb <- mbMinBound, y `isConcretely` (== mb) = false
    | True                                            = liftSym2B (mkSymOpSC (eqOpt falseSW) LessThan)    (<)  x y
  x .<= y
    | Just mb <- mbMinBound, x `isConcretely` (== mb) = true
    | Just mb <- mbMaxBound, y `isConcretely` (== mb) = true
    | True                                            = liftSym2B (mkSymOpSC (eqOpt trueSW) LessEq)       (<=) x y
  x .> y
    | Just mb <- mbMinBound, x `isConcretely` (== mb) = false
    | Just mb <- mbMaxBound, y `isConcretely` (== mb) = false
    | True                                            = liftSym2B (mkSymOpSC (eqOpt falseSW) GreaterThan) (>)  x y
  x .>= y
    | Just mb <- mbMaxBound, x `isConcretely` (== mb) = true
    | Just mb <- mbMinBound, y `isConcretely` (== mb) = true
    | True                                            = liftSym2B (mkSymOpSC (eqOpt trueSW) GreaterEq)    (>=) x y

-- Bool
instance EqSymbolic Bool where
  x .== y = if x == y then true else false

-- Lists
instance EqSymbolic a => EqSymbolic [a] where
  []     .== []     = true
  (x:xs) .== (y:ys) = x .== y &&& xs .== ys
  _      .== _      = false

instance OrdSymbolic a => OrdSymbolic [a] where
  []     .< []     = false
  []     .< _      = true
  _      .< []     = false
  (x:xs) .< (y:ys) = x .< y ||| (x .== y &&& xs .< ys)

-- Maybe
instance EqSymbolic a => EqSymbolic (Maybe a) where
  Nothing .== Nothing = true
  Just a  .== Just b  = a .== b
  _       .== _       = false

instance (OrdSymbolic a) => OrdSymbolic (Maybe a) where
  Nothing .<  Nothing = false
  Nothing .<  _       = true
  Just _  .<  Nothing = false
  Just a  .<  Just b  = a .< b

-- Either
instance (EqSymbolic a, EqSymbolic b) => EqSymbolic (Either a b) where
  Left a  .== Left b  = a .== b
  Right a .== Right b = a .== b
  _       .== _       = false

instance (OrdSymbolic a, OrdSymbolic b) => OrdSymbolic (Either a b) where
  Left a  .< Left b  = a .< b
  Left _  .< Right _ = true
  Right _ .< Left _  = false
  Right a .< Right b = a .< b

-- 2-Tuple
instance (EqSymbolic a, EqSymbolic b) => EqSymbolic (a, b) where
  (a0, b0) .== (a1, b1) = a0 .== a1 &&& b0 .== b1

instance (OrdSymbolic a, OrdSymbolic b) => OrdSymbolic (a, b) where
  (a0, b0) .< (a1, b1) = a0 .< a1 ||| (a0 .== a1 &&& b0 .< b1)

-- 3-Tuple
instance (EqSymbolic a, EqSymbolic b, EqSymbolic c) => EqSymbolic (a, b, c) where
  (a0, b0, c0) .== (a1, b1, c1) = (a0, b0) .== (a1, b1) &&& c0 .== c1

instance (OrdSymbolic a, OrdSymbolic b, OrdSymbolic c) => OrdSymbolic (a, b, c) where
  (a0, b0, c0) .< (a1, b1, c1) = (a0, b0) .< (a1, b1) ||| ((a0, b0) .== (a1, b1) &&& c0 .< c1)

-- 4-Tuple
instance (EqSymbolic a, EqSymbolic b, EqSymbolic c, EqSymbolic d) => EqSymbolic (a, b, c, d) where
  (a0, b0, c0, d0) .== (a1, b1, c1, d1) = (a0, b0, c0) .== (a1, b1, c1) &&& d0 .== d1

instance (OrdSymbolic a, OrdSymbolic b, OrdSymbolic c, OrdSymbolic d) => OrdSymbolic (a, b, c, d) where
  (a0, b0, c0, d0) .< (a1, b1, c1, d1) = (a0, b0, c0) .< (a1, b1, c1) ||| ((a0, b0, c0) .== (a1, b1, c1) &&& d0 .< d1)

-- 5-Tuple
instance (EqSymbolic a, EqSymbolic b, EqSymbolic c, EqSymbolic d, EqSymbolic e) => EqSymbolic (a, b, c, d, e) where
  (a0, b0, c0, d0, e0) .== (a1, b1, c1, d1, e1) = (a0, b0, c0, d0) .== (a1, b1, c1, d1) &&& e0 .== e1

instance (OrdSymbolic a, OrdSymbolic b, OrdSymbolic c, OrdSymbolic d, OrdSymbolic e) => OrdSymbolic (a, b, c, d, e) where
  (a0, b0, c0, d0, e0) .< (a1, b1, c1, d1, e1) = (a0, b0, c0, d0) .< (a1, b1, c1, d1) ||| ((a0, b0, c0, d0) .== (a1, b1, c1, d1) &&& e0 .< e1)

-- 6-Tuple
instance (EqSymbolic a, EqSymbolic b, EqSymbolic c, EqSymbolic d, EqSymbolic e, EqSymbolic f) => EqSymbolic (a, b, c, d, e, f) where
  (a0, b0, c0, d0, e0, f0) .== (a1, b1, c1, d1, e1, f1) = (a0, b0, c0, d0, e0) .== (a1, b1, c1, d1, e1) &&& f0 .== f1

instance (OrdSymbolic a, OrdSymbolic b, OrdSymbolic c, OrdSymbolic d, OrdSymbolic e, OrdSymbolic f) => OrdSymbolic (a, b, c, d, e, f) where
  (a0, b0, c0, d0, e0, f0) .< (a1, b1, c1, d1, e1, f1) =    (a0, b0, c0, d0, e0) .<  (a1, b1, c1, d1, e1)
                                                       ||| ((a0, b0, c0, d0, e0) .== (a1, b1, c1, d1, e1) &&& f0 .< f1)

-- 7-Tuple
instance (EqSymbolic a, EqSymbolic b, EqSymbolic c, EqSymbolic d, EqSymbolic e, EqSymbolic f, EqSymbolic g) => EqSymbolic (a, b, c, d, e, f, g) where
  (a0, b0, c0, d0, e0, f0, g0) .== (a1, b1, c1, d1, e1, f1, g1) = (a0, b0, c0, d0, e0, f0) .== (a1, b1, c1, d1, e1, f1) &&& g0 .== g1

instance (OrdSymbolic a, OrdSymbolic b, OrdSymbolic c, OrdSymbolic d, OrdSymbolic e, OrdSymbolic f, OrdSymbolic g) => OrdSymbolic (a, b, c, d, e, f, g) where
  (a0, b0, c0, d0, e0, f0, g0) .< (a1, b1, c1, d1, e1, f1, g1) =    (a0, b0, c0, d0, e0, f0) .<  (a1, b1, c1, d1, e1, f1)
                                                               ||| ((a0, b0, c0, d0, e0, f0) .== (a1, b1, c1, d1, e1, f1) &&& g0 .< g1)

-- Boolean combinators
instance Boolean SBool where
  true  = literal True
  false = literal False
  bnot  b | b `isConcretely` (== False) = true
          | b `isConcretely` (== True)  = false
          | True                        = liftSym1Bool (mkSymOp1 Not) not b
  a &&& b | a `isConcretely` (== False) || b `isConcretely` (== False) = false
          | a `isConcretely` (== True)                                 = b
          | b `isConcretely` (== True)                                 = a
          | True                                                       = liftSym2Bool (mkSymOpSC opt And) (&&) a b
          where opt x y
                 | x == falseSW || y == falseSW = Just falseSW
                 | x == trueSW                  = Just y
                 | y == trueSW                  = Just x
                 | True                         = Nothing
  a ||| b | a `isConcretely` (== True)  || b `isConcretely` (== True) = true
          | a `isConcretely` (== False)                               = b
          | b `isConcretely` (== False)                               = a
          | True                                                      = liftSym2Bool (mkSymOpSC opt Or)  (||) a b
          where opt x y
                 | x == trueSW || y == trueSW = Just trueSW
                 | x == falseSW               = Just y
                 | y == falseSW               = Just x
                 | True                       = Nothing
  a <+> b | a `isConcretely` (== False) = b
          | b `isConcretely` (== False) = a
          | a `isConcretely` (== True)  = bnot b
          | b `isConcretely` (== True)  = bnot a
          | True                        = liftSym2Bool (mkSymOpSC opt XOr) (<+>) a b
          where opt x y
                 | x == y       = Just falseSW
                 | x == falseSW = Just y
                 | y == falseSW = Just x
                 | True         = Nothing

-- | Returns (symbolic) true if all the elements of the given list are different
allDifferent :: (Eq a, SymWord a) => [SBV a] -> SBool
allDifferent (x:xs@(_:_)) = bAll ((./=) x) xs &&& allDifferent xs
allDifferent _            = true

-- | Returns (symbolic) true if all the elements of the given list are the same
allEqual :: (Eq a, SymWord a) => [SBV a] -> SBool
allEqual (x:xs@(_:_))     = bAll ((.==) x) xs
allEqual _                = true

-- | Returns 1 if the boolean is true, otherwise 0
oneIf :: (Num a, SymWord a) => SBool -> SBV a
oneIf t = ite t 1 0

-- Num instance for symbolic words
instance (Ord a, Num a, SymWord a) => Num (SBV a) where
  fromInteger = literal . fromIntegral
  x + y
    | x `isConcretely` (== 0) = y
    | y `isConcretely` (== 0) = x
    | True                    = liftSym2 (mkSymOp Plus)  (+) x y
  x * y
    | x `isConcretely` (== 0) = 0
    | y `isConcretely` (== 0) = 0
    | x `isConcretely` (== 1) = y
    | y `isConcretely` (== 1) = x
    | True                    = liftSym2 (mkSymOp Times) (*) x y
  x - y
    | y `isConcretely` (== 0) = x
    | True                    = liftSym2 (mkSymOp Minus) (-) x y
  abs a
   | hasSign a = ite (a .< 0) (-a) a
   | True      = a
  signum a
   | hasSign a = ite (a .< 0) (-1) (ite (a .== 0) 0 1)
   | True      = oneIf (a ./= 0)

-- NB. The default definition of "testBit" relies on equality,
-- which is not available for symbolic SBV's. There is no
-- way to implement testBit to return Bool, obviously; instead use bitValue
-- Also, in the optimizations below, use of -1 is valid as
-- -1 has all bits set to True for both signed and unsigned values
instance (Bits a, SymWord a) => Bits (SBV a) where
  x .&. y
    | x `isConcretely` (== 0)  = 0
    | x `isConcretely` (== -1) = y
    | y `isConcretely` (== 0)  = 0
    | y `isConcretely` (== -1) = x
    | True                     = liftSym2 (mkSymOp  And) (.&.) x y
  x .|. y
    | x `isConcretely` (== 0)  = y
    | x `isConcretely` (== -1) = -1
    | y `isConcretely` (== 0)  = x
    | y `isConcretely` (== -1) = -1
    | True                     = liftSym2 (mkSymOp  Or)  (.|.) x y
  x `xor` y
    | x `isConcretely` (== 0)  = y
    | y `isConcretely` (== 0)  = x
    | True                     = liftSym2 (mkSymOp  XOr) xor x y
  complement = liftSym1 (mkSymOp1 Not) complement
  bitSize  _ = intSizeOf (undefined :: a)
  isSigned _ = hasSign   (undefined :: a)
  shiftL x y
    | y < 0                = shiftR x (-y)
    | y == 0               = x
    | True                 = liftSym1 (mkSymOp1 (Shl y)) (`shiftL` y) x
  shiftR x y
    | y < 0                = shiftL x (-y)
    | y == 0               = x
    | True                 = liftSym1 (mkSymOp1 (Shr y)) (`shiftR` y) x
  rotateL x y
    | y < 0                = rotateR x (-y)
    | y == 0               = x
    | not (isInfPrec x)    = let sz = bitSize x in liftSym1 (mkSymOp1 (Rol (y `mod` sz))) (rot True sz y) x
    | True                 = shiftL x y   -- for unbounded Integers, rotateL is the same as shiftL in Haskell
  rotateR x y
    | y < 0                = rotateL x (-y)
    | y == 0               = x
    | not (isInfPrec x)    = let sz = bitSize x in liftSym1 (mkSymOp1 (Ror (y `mod` sz))) (rot False sz y) x
    | True                 = shiftR x y   -- for unbounded integers, rotateR is the same as shiftR in Haskell

-- Since the underlying representation is just Integers, rotations has to be careful on the bit-size
rot :: Bool -> Int -> Int -> Integer -> Integer
rot toLeft sz amt x
  | sz < 2 = x
  | True   = (norm x y') `shiftL` y  .|. norm (x `shiftR` y') y
  where (y, y') | toLeft = (amt `mod` sz, sz - y)
                | True   = (sz - y', amt `mod` sz)
        norm v s = v .&. ((1 `shiftL` s) - 1)

-- | Replacement for 'testBit'. Since 'testBit' requires a 'Bool' to be returned,
-- we cannot implement it for symbolic words. Index 0 is the least-significant bit.
bitValue :: (Bits a, SymWord a) => SBV a -> Int -> SBool
bitValue x i = (x .&. bit i) ./= 0

-- | Generalization of 'setBit' based on a symbolic boolean. Note that 'setBit' and
-- 'clearBit' are still available on Symbolic words, this operation comes handy when
-- the condition to set/clear happens to be symbolic
setBitTo :: (Bits a, SymWord a) => SBV a -> Int -> SBool -> SBV a
setBitTo x i b = ite b (setBit x i) (clearBit x i)

-- | Little-endian blasting of a word into its bits. Also see the 'FromBits' class
blastLE :: (Bits a, SymWord a) => SBV a -> [SBool]
blastLE x
 | isInfPrec x = error "SBV.blastLE: Called on an infinite precision value"
 | True        = map (bitValue x) [0 .. (intSizeOf x)-1]

-- | Big-endian blasting of a word into its bits. Also see the 'FromBits' class
blastBE :: (Bits a, SymWord a) => SBV a -> [SBool]
blastBE = reverse . blastLE

-- | Least significant bit of a word, always stored at index 0
lsb :: (Bits a, SymWord a) => SBV a -> SBool
lsb x = bitValue x 0

-- | Most significant bit of a word, always stored at the last position
msb :: (Bits a, SymWord a) => SBV a -> SBool
msb x
 | isInfPrec x = error "SBV.msb: Called on an infinite precision value"
 | True        = bitValue x ((intSizeOf x) - 1)

-- Enum instance. These instances are suitable for use with concrete values,
-- and will be less useful for symbolic values around. Note that `fromEnum` requires
-- a concrete argument for obvious reasons. Other variants (succ, pred, [x..]) etc are similarly
-- limited. While symbolic variants can be defined for many of these, they will just diverge
-- as final sizes cannot be determined statically.
instance (Bounded a, Integral a, Num a, SymWord a) => Enum (SBV a) where
  succ x
    | v == (maxBound :: a) = error $ "Enum.succ{" ++ showType x ++ "}: tried to take `succ' of maxBound"
    | True                 = fromIntegral $ v + 1
    where v = enumCvt "succ" x
  pred x
    | v == (minBound :: a) = error $ "Enum.pred{" ++ showType x ++ "}: tried to take `pred' of minBound"
    | True                 = fromIntegral $ v - 1
    where v = enumCvt "pred" x
  toEnum x
    | xi < fromIntegral (minBound :: a) || xi > fromIntegral (maxBound :: a)
    = error $ "Enum.toEnum{" ++ showType r ++ "}: " ++ show x ++ " is out-of-bounds " ++ show (minBound :: a, maxBound :: a)
    | True
    = r
    where xi :: Integer
          xi = fromIntegral x
          r  :: SBV a
          r  = fromIntegral x
  fromEnum x
     | r < fromIntegral (minBound :: Int) || r > fromIntegral (maxBound :: Int)
     = error $ "Enum.fromEnum{" ++ showType x ++ "}:  value " ++ show r ++ " is outside of Int's bounds " ++ show (minBound :: Int, maxBound :: Int)
     | True
     = fromIntegral r
    where r :: Integer
          r = enumCvt "fromEnum" x
  enumFrom x = map fromIntegral [xi .. fromIntegral (maxBound :: a)]
     where xi :: Integer
           xi = enumCvt "enumFrom" x
  enumFromThen x y
     | yi >= xi  = map fromIntegral [xi, yi .. fromIntegral (maxBound :: a)]
     | True      = map fromIntegral [xi, yi .. fromIntegral (minBound :: a)]
       where xi, yi :: Integer
             xi = enumCvt "enumFromThen.x" x
             yi = enumCvt "enumFromThen.y" y
  enumFromThenTo x y z = map fromIntegral [xi, yi .. zi]
       where xi, yi, zi :: Integer
             xi = enumCvt "enumFromThenTo.x" x
             yi = enumCvt "enumFromThenTo.y" y
             zi = enumCvt "enumFromThenTo.z" z

-- | Helper function for use in enum operations
enumCvt :: (SymWord a, Integral a, Num b) => String -> SBV a -> b
enumCvt w x = case unliteral x of
                Nothing -> error $ "Enum." ++ w ++ "{" ++ showType x ++ "}: Called on symbolic value " ++ show x
                Just v  -> fromIntegral v

-- | The 'BVDivisible' class captures the essence of division of words.
-- Unfortunately we cannot use Haskell's 'Integral' class since the 'Real'
-- and 'Enum' superclasses are not implementable for symbolic bit-vectors.
-- However, 'quotRem' makes perfect sense, and the 'BVDivisible' class captures
-- this operation. One issue is how division by 0 behaves. The verification
-- technology requires total functions, and there are several design choices
-- here. We follow Isabelle/HOL approach of assigning the value 0 for division
-- by 0. Therefore, we impose the following law:
--
--     @ x `bvQuotRem` 0 = (0, x) @
--
-- Note that our instances implement this law even when @x@ is @0@ itself.
--
-- Minimal complete definition: 'bvQuotRem'
class BVDivisible a where
  bvQuotRem :: a -> a -> (a, a)

instance BVDivisible Word64 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Int64 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Word32 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Int32 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Word16 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Int16 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Word8 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Int8 where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible Integer where
  bvQuotRem x 0 = (0, x)
  bvQuotRem x y = x `quotRem` y

instance BVDivisible CW where
  bvQuotRem x y
    | cwSameType x y = let (r1, r2) = bvQuotRem (cwVal x) (cwVal y)
                       in (x { cwVal = r1 }, y { cwVal = r2 })
  bvQuotRem x y = error $ "SBV.liftQRem: impossible, unexpected args received: " ++ show (x, y)

instance BVDivisible SWord64 where
  bvQuotRem = liftQRem

instance BVDivisible SInt64 where
  bvQuotRem = liftQRem

instance BVDivisible SWord32 where
  bvQuotRem = liftQRem

instance BVDivisible SInt32 where
  bvQuotRem = liftQRem

instance BVDivisible SWord16 where
  bvQuotRem = liftQRem

instance BVDivisible SInt16 where
  bvQuotRem = liftQRem

instance BVDivisible SWord8 where
  bvQuotRem = liftQRem

instance BVDivisible SInt8 where
  bvQuotRem = liftQRem

instance BVDivisible SInteger where
  bvQuotRem = liftQRem

liftQRem :: (SymWord a, Num a, BVDivisible a) => SBV a -> SBV a -> (SBV a, SBV a)
liftQRem x y = ite (y .== 0) (0, x) (qr x y)
  where qr (SBV sgnsz (Left a)) (SBV _ (Left b)) = let (q, r) = bvQuotRem a b in (SBV sgnsz (Left q), SBV sgnsz (Left r))
        qr a@(SBV sgnsz _)      b                = (SBV sgnsz (Right (cache (mk Quot))), SBV sgnsz (Right (cache (mk Rem))))
                where mk o st = do sw1 <- sbvToSW st a
                                   sw2 <- sbvToSW st b
                                   mkSymOp o st sgnsz sw1 sw2

-- Quickcheck interface

-- The Arbitrary instance for SFunArray returns an array initialized
-- to an arbitrary element
instance (SymWord b, Arbitrary b) => Arbitrary (SFunArray a b) where
  arbitrary = arbitrary >>= \r -> return $ SFunArray (const r)

instance (SymWord a, Arbitrary a) => Arbitrary (SBV a) where
  arbitrary = arbitrary >>= return . literal

-- |  Symbolic choice operator, parameterized via a class
-- 'select' is a total-indexing function, with the default.
--
-- Minimal complete definition: 'symbolicMerge'
class Mergeable a where
   -- | Merge two values based on the condition
   symbolicMerge :: SBool -> a -> a -> a
   -- | Choose one or the other element, based on the condition.
   -- This is similar to 'symbolicMerge', but it has a default
   -- implementation that makes sure it's short-cut if the condition is concrete
   ite           :: SBool -> a -> a -> a
   -- | Total indexing operation. @select xs default index@ is intuitively
   -- the same as @xs !! index@, except it evaluates to @default@ if @index@
   -- overflows
   select        :: (Bits b, SymWord b, Integral b) => [a] -> a -> SBV b -> a
   -- default definitions
   ite s a b
    | Just t <- unliteral s = if t then a else b
    | True                  = symbolicMerge s a b
   select [] err _   = err
   select xs err ind
    | hasSign ind    = ite (ind .< 0) err $ result
    | True           = result
    where result = go xs $ reverse (zip [(0::Integer)..] bits)
          bits   = map (ind `bitValue`) [0 .. bitSize ind - 1]
          go []    _            = err
          go (x:_) []           = x
          go elts  ((n, b):nbs) = let (ys, zs) = genericSplitAt ((2::Integer) ^ n) elts
                                  in ite b (go zs nbs) (go ys nbs)

-- SBV
instance SymWord a => Mergeable (SBV a) where
  symbolicMerge t a b
   | Just c1 <- unliteral a, Just c2 <- unliteral b, c1 == c2
   = a
   | True
   = SBV sgnsz $ Right $ cache c
    where sgnsz = (hasSign a, sizeOf a)
          c st = do swt <- sbvToSW st t
                    case () of
                      () | swt == trueSW  -> sbvToSW st a
                      () | swt == falseSW -> sbvToSW st b
                      () -> do swa <- sbvToSW st a
                               swb <- sbvToSW st b
                               if swa == swb
                                  then return swa
                                  else newExpr st sgnsz (SBVApp Ite [swt, swa, swb])
  -- Custom version of select that translates to SMT-Lib tables at the base type of words
  select xs err ind
    | Just i <- unliteral ind
    = let i' :: Integer
          i' = fromIntegral i
      in if i' < 0 || i' >= genericLength xs then err else genericIndex xs i'
  select [] err _   = err
  select xs err ind = SBV sgnszElt $ Right $ cache r
     where sgnszInd = (hasSign ind, sizeOf ind)
           sgnszElt = (hasSign err, sizeOf err)
           r st  = do sws <- mapM (sbvToSW st) xs
                      swe <- sbvToSW st err
                      if all (== swe) sws  -- off-chance that all elts are the same
                         then return swe
                         else do idx <- getTableIndex st sgnszInd sgnszElt sws
                                 swi <- sbvToSW st ind
                                 let len = length xs
                                 newExpr st sgnszElt (SBVApp (LkUp (idx, sgnszInd, sgnszElt, len) swi swe) [])

-- Unit
instance Mergeable () where
   symbolicMerge _ _ _ = ()
   select _ _ _ = ()

-- Mergeable instances for List/Maybe/Either/Array are useful, but can
-- throw exceptions if there is no structural matching of the results
-- It's a question whether we should really keep them..

-- Lists
instance Mergeable a => Mergeable [a] where
  symbolicMerge t xs ys
    | lxs == lys = zipWith (symbolicMerge t) xs ys
    | True       = error $ "SBV.Mergeable.List: No least-upper-bound for lists of differing size " ++ show (lxs, lys)
    where (lxs, lys) = (length xs, length ys)

-- Maybe
instance Mergeable a => Mergeable (Maybe a) where
  symbolicMerge _ Nothing  Nothing  = Nothing
  symbolicMerge t (Just a) (Just b) = Just $ symbolicMerge t a b
  symbolicMerge _ a b = error $ "SBV.Mergeable.Maybe: No least-upper-bound for " ++ show (k a, k b)
      where k Nothing = "Nothing"
            k _       = "Just"

-- Either
instance (Mergeable a, Mergeable b) => Mergeable (Either a b) where
  symbolicMerge t (Left a)  (Left b)  = Left  $ symbolicMerge t a b
  symbolicMerge t (Right a) (Right b) = Right $ symbolicMerge t a b
  symbolicMerge _ a b = error $ "SBV.Mergeable.Either: No least-upper-bound for " ++ show (k a, k b)
     where k (Left _)  = "Left"
           k (Right _) = "Right"

-- Arrays
instance (Ix a, Mergeable b) => Mergeable (Array a b) where
  symbolicMerge t a b
    | ba == bb = listArray ba (zipWith (symbolicMerge t) (elems a) (elems b))
    | True     = error $ "SBV.Mergeable.Array: No least-upper-bound for rangeSizes" ++ show (k ba, k bb)
    where [ba, bb] = map bounds [a, b]
          k = rangeSize

-- Functions
instance Mergeable b => Mergeable (a -> b) where
  symbolicMerge t f g = \x -> symbolicMerge t (f x) (g x)
  select xs err ind   = \x -> select (map ($ x) xs) (err x) ind

-- 2-Tuple
instance (Mergeable a, Mergeable b) => Mergeable (a, b) where
  symbolicMerge t (i0, i1) (j0, j1) = (i i0 j0, i i1 j1)
    where i a b = symbolicMerge t a b
  select xs (err1, err2) ind = (select as err1 ind, select bs err2 ind)
    where (as, bs) = unzip xs

-- 3-Tuple
instance (Mergeable a, Mergeable b, Mergeable c) => Mergeable (a, b, c) where
  symbolicMerge t (i0, i1, i2) (j0, j1, j2) = (i i0 j0, i i1 j1, i i2 j2)
    where i a b = symbolicMerge t a b
  select xs (err1, err2, err3) ind = (select as err1 ind, select bs err2 ind, select cs err3 ind)
    where (as, bs, cs) = unzip3 xs

-- 4-Tuple
instance (Mergeable a, Mergeable b, Mergeable c, Mergeable d) => Mergeable (a, b, c, d) where
  symbolicMerge t (i0, i1, i2, i3) (j0, j1, j2, j3) = (i i0 j0, i i1 j1, i i2 j2, i i3 j3)
    where i a b = symbolicMerge t a b
  select xs (err1, err2, err3, err4) ind = (select as err1 ind, select bs err2 ind, select cs err3 ind, select ds err4 ind)
    where (as, bs, cs, ds) = unzip4 xs

-- 5-Tuple
instance (Mergeable a, Mergeable b, Mergeable c, Mergeable d, Mergeable e) => Mergeable (a, b, c, d, e) where
  symbolicMerge t (i0, i1, i2, i3, i4) (j0, j1, j2, j3, j4) = (i i0 j0, i i1 j1, i i2 j2, i i3 j3, i i4 j4)
    where i a b = symbolicMerge t a b
  select xs (err1, err2, err3, err4, err5) ind = (select as err1 ind, select bs err2 ind, select cs err3 ind, select ds err4 ind, select es err5 ind)
    where (as, bs, cs, ds, es) = unzip5 xs

-- 6-Tuple
instance (Mergeable a, Mergeable b, Mergeable c, Mergeable d, Mergeable e, Mergeable f) => Mergeable (a, b, c, d, e, f) where
  symbolicMerge t (i0, i1, i2, i3, i4, i5) (j0, j1, j2, j3, j4, j5) = (i i0 j0, i i1 j1, i i2 j2, i i3 j3, i i4 j4, i i5 j5)
    where i a b = symbolicMerge t a b
  select xs (err1, err2, err3, err4, err5, err6) ind = (select as err1 ind, select bs err2 ind, select cs err3 ind, select ds err4 ind, select es err5 ind, select fs err6 ind)
    where (as, bs, cs, ds, es, fs) = unzip6 xs

-- 7-Tuple
instance (Mergeable a, Mergeable b, Mergeable c, Mergeable d, Mergeable e, Mergeable f, Mergeable g) => Mergeable (a, b, c, d, e, f, g) where
  symbolicMerge t (i0, i1, i2, i3, i4, i5, i6) (j0, j1, j2, j3, j4, j5, j6) = (i i0 j0, i i1 j1, i i2 j2, i i3 j3, i i4 j4, i i5 j5, i i6 j6)
    where i a b = symbolicMerge t a b
  select xs (err1, err2, err3, err4, err5, err6, err7) ind = (select as err1 ind, select bs err2 ind, select cs err3 ind, select ds err4 ind, select es err5 ind, select fs err6 ind, select gs err7 ind)
    where (as, bs, cs, ds, es, fs, gs) = unzip7 xs

-- Bounded instances
instance (SymWord a, Bounded a) => Bounded (SBV a) where
  minBound = literal minBound
  maxBound = literal maxBound

-- Arrays

-- SArrays are both "EqSymbolic" and "Mergeable"
instance EqSymbolic (SArray a b) where
  (SArray _ a) .== (SArray _ b) = SBV (False, Size (Just 1)) $ Right $ cache c
    where c st = do ai <- uncacheAI a st
                    bi <- uncacheAI b st
                    newExpr st (False, Size (Just 1)) (SBVApp (ArrEq ai bi) [])

instance SymWord b => Mergeable (SArray a b) where
  symbolicMerge = mergeArrays

-- SFunArrays are only "Mergeable". Although a brute
-- force equality can be defined, any non-toy instance
-- will suffer from efficiency issues; so we don't define it
instance SymArray SFunArray where
  newArray _        = newArray_ -- the name is irrelevant in this case
  newArray_  mbiVal = return $ SFunArray $ const $ maybe (error "Reading from an uninitialized array entry") id mbiVal
  readArray  (SFunArray f) a   = f a
  resetArray (SFunArray _) a   = SFunArray $ const a
  writeArray (SFunArray f) a b = SFunArray (\a' -> ite (a .== a') b (f a'))
  mergeArrays t (SFunArray f) (SFunArray g) = SFunArray (\x -> ite t (f x) (g x))

instance SymWord b => Mergeable (SFunArray a b) where
  symbolicMerge = mergeArrays

-- | An uninterpreted function handle. This is the handle to be used for
-- adding axioms about uninterpreted constants/functions. Note that
-- we will leave this abstract for safety purposes
newtype SBVUF = SBVUF String

-- | Get the name associated with the uninterpreted-value; useful when
-- constructing axioms about this UI.
sbvUFName :: SBVUF -> String
sbvUFName (SBVUF s) = s

-- The name we use for translating the UF constants to SMT-Lib..
mkUFName :: String -> SBVUF
mkUFName nm = SBVUF $ "uninterpreted_" ++ nm

-- | Uninterpreted constants and functions. An uninterpreted constant is
-- a value that is indexed by its name. The only property the prover assumes
-- about these values are that they are equivalent to themselves; i.e., (for
-- functions) they return the same results when applied to same arguments.
-- We support uninterpreted-functions as a general means of black-box'ing
-- operations that are /irrelevant/ for the purposes of the proof; i.e., when
-- the proofs can be performed without any knowledge about the function itself.
--
-- Minimal complete definition: 'uninterpretWithHandle'. However, most instances in
-- practice are already provided by SBV, so end-users should not need to define their
-- own instances.
class Uninterpreted a where
  -- | Uninterpret a value, receiving an object that can be used instead. Use this version
  -- when you do not need to add an axiom about this value.
  uninterpret :: String -> a
  -- | Uninterpret a value, but also get a handle to the resulting object. This handle
  -- can be used to add axioms for this object. (See 'addAxiom'.)
  uninterpretWithHandle :: String -> (SBVUF, a)
  -- | Uninterpret a value, only for the purposes of code-generation. For execution
  -- and verification the value is used as is. For code-generation, the alternate
  -- definition is used. This is useful when we want to take advantage of native
  -- libraries on the target languages.
  cgUninterpret :: String -> [String] -> a -> a
  -- | Most generalized form of uninterpretation, this function should not be needed
  -- by end-user-code, but is rather useful for the library development.
  sbvUninterpret :: Maybe ([String], a) -> String -> (SBVUF, a)

  -- minimal complete definition: 'sbvUninterpret'
  uninterpret             = snd . uninterpretWithHandle
  uninterpretWithHandle   = sbvUninterpret Nothing
  cgUninterpret nm code v = snd $ sbvUninterpret (Just (code, v)) nm

-- Plain constants
instance HasSignAndSize a => Uninterpreted (SBV a) where
  sbvUninterpret mbCgData nm
     | Just (_, v) <- mbCgData = (mkUFName nm, v)
     | True                    = (mkUFName nm, SBV sgnsza $ Right $ cache result)
    where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
          result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st v
                    | True = do newUninterpreted st nm (SBVType [sgnsza]) (fst `fmap` mbCgData)
                                newExpr st sgnsza $ SBVApp (Uninterpreted nm) []

-- Forcing an argument; this is a necessary evil to make sure all the arguments
-- to an uninterpreted function are evaluated before called; the semantics of
-- such functions is necessarily strict; deviating from Haskell's
forceArg :: SW -> IO ()
forceArg (SW (b, s) n) = b `seq` s `seq` n `seq` return ()

-- Functions of one argument
instance (SymWord b, HasSignAndSize a) => Uninterpreted (SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0
           | Just (_, v) <- mbCgData, isConcrete arg0
           = v arg0
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0)
                           | True = do newUninterpreted st nm (SBVType [sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                       sw0 <- sbvToSW st arg0
                                       mapM_ forceArg [sw0]
                                       newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0]

-- Functions of two arguments
instance (SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted (SBV c -> SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0 arg1
           | Just (_, v) <- mbCgData, isConcrete arg0, isConcrete arg1
           = v arg0 arg1
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 sgnszc = (hasSign (undefined :: c), sizeOf (undefined :: c))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0 arg1)
                           | True = do newUninterpreted st nm (SBVType [sgnszc, sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                       sw0 <- sbvToSW st arg0
                                       sw1 <- sbvToSW st arg1
                                       mapM_ forceArg [sw0, sw1]
                                       newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0, sw1]

-- Functions of three arguments
instance (SymWord d, SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted (SBV d -> SBV c -> SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0 arg1 arg2
           | Just (_, v) <- mbCgData, isConcrete arg0, isConcrete arg1, isConcrete arg2
           = v arg0 arg1 arg2
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 sgnszc = (hasSign (undefined :: c), sizeOf (undefined :: c))
                 sgnszd = (hasSign (undefined :: d), sizeOf (undefined :: d))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0 arg1 arg2)
                           | True = do newUninterpreted st nm (SBVType [sgnszd, sgnszc, sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                       sw0 <- sbvToSW st arg0
                                       sw1 <- sbvToSW st arg1
                                       sw2 <- sbvToSW st arg2
                                       mapM_ forceArg [sw0, sw1, sw2]
                                       newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0, sw1, sw2]

-- Functions of four arguments
instance (SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted (SBV e -> SBV d -> SBV c -> SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0 arg1 arg2 arg3
           | Just (_, v) <- mbCgData, isConcrete arg0, isConcrete arg1, isConcrete arg2, isConcrete arg3
           = v arg0 arg1 arg2 arg3
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 sgnszc = (hasSign (undefined :: c), sizeOf (undefined :: c))
                 sgnszd = (hasSign (undefined :: d), sizeOf (undefined :: d))
                 sgnsze = (hasSign (undefined :: e), sizeOf (undefined :: e))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0 arg1 arg2 arg3)
                           | True = do newUninterpreted st nm (SBVType [sgnsze, sgnszd, sgnszc, sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                       sw0 <- sbvToSW st arg0
                                       sw1 <- sbvToSW st arg1
                                       sw2 <- sbvToSW st arg2
                                       sw3 <- sbvToSW st arg3
                                       mapM_ forceArg [sw0, sw1, sw2, sw3]
                                       newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0, sw1, sw2, sw3]

-- Functions of five arguments
instance (SymWord f, SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted (SBV f -> SBV e -> SBV d -> SBV c -> SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0 arg1 arg2 arg3 arg4
           | Just (_, v) <- mbCgData, isConcrete arg0, isConcrete arg1, isConcrete arg2, isConcrete arg3, isConcrete arg4
           = v arg0 arg1 arg2 arg3 arg4
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 sgnszc = (hasSign (undefined :: c), sizeOf (undefined :: c))
                 sgnszd = (hasSign (undefined :: d), sizeOf (undefined :: d))
                 sgnsze = (hasSign (undefined :: e), sizeOf (undefined :: e))
                 sgnszf = (hasSign (undefined :: f), sizeOf (undefined :: f))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0 arg1 arg2 arg3 arg4)
                           | True = do newUninterpreted st nm (SBVType [sgnszf, sgnsze, sgnszd, sgnszc, sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                       sw0 <- sbvToSW st arg0
                                       sw1 <- sbvToSW st arg1
                                       sw2 <- sbvToSW st arg2
                                       sw3 <- sbvToSW st arg3
                                       sw4 <- sbvToSW st arg4
                                       mapM_ forceArg [sw0, sw1, sw2, sw3, sw4]
                                       newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0, sw1, sw2, sw3, sw4]

-- Functions of six arguments
instance (SymWord g, SymWord f, SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted (SBV g -> SBV f -> SBV e -> SBV d -> SBV c -> SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0 arg1 arg2 arg3 arg4 arg5
           | Just (_, v) <- mbCgData, isConcrete arg0, isConcrete arg1, isConcrete arg2, isConcrete arg3, isConcrete arg4, isConcrete arg5
           = v arg0 arg1 arg2 arg3 arg4 arg5
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 sgnszc = (hasSign (undefined :: c), sizeOf (undefined :: c))
                 sgnszd = (hasSign (undefined :: d), sizeOf (undefined :: d))
                 sgnsze = (hasSign (undefined :: e), sizeOf (undefined :: e))
                 sgnszf = (hasSign (undefined :: f), sizeOf (undefined :: f))
                 sgnszg = (hasSign (undefined :: g), sizeOf (undefined :: g))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0 arg1 arg2 arg3 arg4 arg5)
                           | True = do newUninterpreted st nm (SBVType [sgnszg, sgnszf, sgnsze, sgnszd, sgnszc, sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                       sw0 <- sbvToSW st arg0
                                       sw1 <- sbvToSW st arg1
                                       sw2 <- sbvToSW st arg2
                                       sw3 <- sbvToSW st arg3
                                       sw4 <- sbvToSW st arg4
                                       sw5 <- sbvToSW st arg5
                                       mapM_ forceArg [sw0, sw1, sw2, sw3, sw4, sw5]
                                       newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0, sw1, sw2, sw3, sw4, sw5]

-- Functions of seven arguments
instance (SymWord h, SymWord g, SymWord f, SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a)
            => Uninterpreted (SBV h -> SBV g -> SBV f -> SBV e -> SBV d -> SBV c -> SBV b -> SBV a) where
  sbvUninterpret mbCgData nm = (mkUFName nm, f)
    where f arg0 arg1 arg2 arg3 arg4 arg5 arg6
           | Just (_, v) <- mbCgData, isConcrete arg0, isConcrete arg1, isConcrete arg2, isConcrete arg3, isConcrete arg4, isConcrete arg5, isConcrete arg6
           = v arg0 arg1 arg2 arg3 arg4 arg5 arg6
           | True
           = SBV sgnsza $ Right $ cache result
           where sgnsza = (hasSign (undefined :: a), sizeOf (undefined :: a))
                 sgnszb = (hasSign (undefined :: b), sizeOf (undefined :: b))
                 sgnszc = (hasSign (undefined :: c), sizeOf (undefined :: c))
                 sgnszd = (hasSign (undefined :: d), sizeOf (undefined :: d))
                 sgnsze = (hasSign (undefined :: e), sizeOf (undefined :: e))
                 sgnszf = (hasSign (undefined :: f), sizeOf (undefined :: f))
                 sgnszg = (hasSign (undefined :: g), sizeOf (undefined :: g))
                 sgnszh = (hasSign (undefined :: h), sizeOf (undefined :: h))
                 result st | Just (_, v) <- mbCgData, inProofMode st = sbvToSW st (v arg0 arg1 arg2 arg3 arg4 arg5 arg6)
                          | True = do newUninterpreted st nm (SBVType [sgnszh, sgnszg, sgnszf, sgnsze, sgnszd, sgnszc, sgnszb, sgnsza]) (fst `fmap` mbCgData)
                                      sw0 <- sbvToSW st arg0
                                      sw1 <- sbvToSW st arg1
                                      sw2 <- sbvToSW st arg2
                                      sw3 <- sbvToSW st arg3
                                      sw4 <- sbvToSW st arg4
                                      sw5 <- sbvToSW st arg5
                                      sw6 <- sbvToSW st arg6
                                      mapM_ forceArg [sw0, sw1, sw2, sw3, sw4, sw5, sw6]
                                      newExpr st sgnsza $ SBVApp (Uninterpreted nm) [sw0, sw1, sw2, sw3, sw4, sw5, sw6]

-- Uncurried functions of two arguments
instance (SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted ((SBV c, SBV b) -> SBV a) where
  sbvUninterpret mbCgData nm = let (h, f) = sbvUninterpret (uc2 `fmap` mbCgData) nm in (h, \(arg0, arg1) -> f arg0 arg1)
    where uc2 (cs, fn) = (cs, \a b -> fn (a, b))

-- Uncurried functions of three arguments
instance (SymWord d, SymWord c, SymWord b, HasSignAndSize a) => Uninterpreted ((SBV d, SBV c, SBV b) -> SBV a) where
  sbvUninterpret mbCgData nm = let (h, f) = sbvUninterpret (uc3 `fmap` mbCgData) nm in (h, \(arg0, arg1, arg2) -> f arg0 arg1 arg2)
    where uc3 (cs, fn) = (cs, \a b c -> fn (a, b, c))

-- Uncurried functions of four arguments
instance (SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a)
            => Uninterpreted ((SBV e, SBV d, SBV c, SBV b) -> SBV a) where
  sbvUninterpret mbCgData nm = let (h, f) = sbvUninterpret (uc4 `fmap` mbCgData) nm in (h, \(arg0, arg1, arg2, arg3) -> f arg0 arg1 arg2 arg3)
    where uc4 (cs, fn) = (cs, \a b c d -> fn (a, b, c, d))

-- Uncurried functions of five arguments
instance (SymWord f, SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a)
            => Uninterpreted ((SBV f, SBV e, SBV d, SBV c, SBV b) -> SBV a) where
  sbvUninterpret mbCgData nm = let (h, f) = sbvUninterpret (uc5 `fmap` mbCgData) nm in (h, \(arg0, arg1, arg2, arg3, arg4) -> f arg0 arg1 arg2 arg3 arg4)
    where uc5 (cs, fn) = (cs, \a b c d e -> fn (a, b, c, d, e))

-- Uncurried functions of six arguments
instance (SymWord g, SymWord f, SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a)
            => Uninterpreted ((SBV g, SBV f, SBV e, SBV d, SBV c, SBV b) -> SBV a) where
  sbvUninterpret mbCgData nm = let (h, f) = sbvUninterpret (uc6 `fmap` mbCgData) nm in (h, \(arg0, arg1, arg2, arg3, arg4, arg5) -> f arg0 arg1 arg2 arg3 arg4 arg5)
    where uc6 (cs, fn) = (cs, \a b c d e f -> fn (a, b, c, d, e, f))

-- Uncurried functions of seven arguments
instance (SymWord h, SymWord g, SymWord f, SymWord e, SymWord d, SymWord c, SymWord b, HasSignAndSize a)
            => Uninterpreted ((SBV h, SBV g, SBV f, SBV e, SBV d, SBV c, SBV b) -> SBV a) where
  sbvUninterpret mbCgData nm = let (h, f) = sbvUninterpret (uc7 `fmap` mbCgData) nm in (h, \(arg0, arg1, arg2, arg3, arg4, arg5, arg6) -> f arg0 arg1 arg2 arg3 arg4 arg5 arg6)
    where uc7 (cs, fn) = (cs, \a b c d e f g -> fn (a, b, c, d, e, f, g))

-- Quickcheck interface on symbolic-booleans..
instance Testable SBool where
  property (SBV _ (Left b)) = property (cwToBool b)
  property s                = error $ "Cannot quick-check in the presence of uninterpreted constants! (" ++ show s ++ ")"

instance Testable (Symbolic SBool) where
  property m = QC.whenFail (putStrLn msg) $ QC.monadicIO test
    where test = do die <- QC.run $ do (r, p) <- runSymbolic' QuickCheck (m >>= output)
                                       case () of
                                         _ | isSymbolic r        -> error $ "Cannot quick-check in the presence of uninterpreted constants! (" ++ show r ++ ")"
                                         _ | r `isConcretely` id -> return False
                                         _                       -> do putStrLn $ complain (getQCInfo p)
                                                                       return True
                    when die $ fail "Falsifiable"
          msg = "*** SBV: See the custom counter example reported above."
          complain []     = "*** SBV Counter Example: Predicate contains no universally quantified variables."
          complain qcInfo = intercalate "\n" $ "*** SBV Counter Example:" : map (("  " ++) . info) qcInfo
            where maxLen = maximum (0:[length s | (s, _) <- qcInfo])
                  shN s = s ++ replicate (maxLen - length s) ' '
                  info (n, cw) = shN n ++ " = " ++ show cw

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.TestSuite.Puzzles.DogCatMouse
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Test suite for Data.SBV.Examples.Puzzles.DogCatMouse
-----------------------------------------------------------------------------

module Data.SBV.TestSuite.Puzzles.DogCatMouse(testSuite) where

import Data.SBV
import Data.SBV.Internals
import Data.SBV.Examples.Puzzles.DogCatMouse

-- Test suite
testSuite :: SBVTestSuite
testSuite = mkTestSuite $ \goldCheck -> test [
  "dog cat mouse" ~: allSat p `goldCheck` "dogCatMouse.gold"
 ]
 where p = do d <- exists "d"
              c <- exists "c"
              m <- exists "m"
              return $ puzzle d c m

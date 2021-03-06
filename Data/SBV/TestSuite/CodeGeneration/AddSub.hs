-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.TestSuite.CodeGeneration.AddSub
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Test suite for Data.SBV.Examples.CodeGeneration.AddSub
-----------------------------------------------------------------------------

module Data.SBV.TestSuite.CodeGeneration.AddSub(testSuite) where

import Data.SBV
import Data.SBV.Internals
import Data.SBV.Examples.CodeGeneration.AddSub

-- Test suite
testSuite :: SBVTestSuite
testSuite = mkTestSuite $ \goldCheck -> test [
   "addSub" ~: code `goldCheck` "addSub.gold"
 ]
 where code = compileToC' "addSub" $ do
                cgSetDriverValues [76, 92]
                cgPerformRTCs True
                x <- cgInput "x"
                y <- cgInput "y"
                let (s, d) = addSub x y
                cgOutput "sum" s
                cgOutput "dif" d

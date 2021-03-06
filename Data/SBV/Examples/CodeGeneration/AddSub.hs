-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Examples.CodeGeneration.AddSub
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Simple code generation example.
-----------------------------------------------------------------------------

module Data.SBV.Examples.CodeGeneration.AddSub where

import Data.SBV

-- | Simple function that returns add/sum of args
addSub :: SWord8 -> SWord8 -> (SWord8, SWord8)
addSub x y = (x+y, x-y)

-- | Generate C code for addSub. This will place the files in a directory called @genAddSub@,
-- generating the following files:
--
-- File: @Makefile@
--
-- > # Makefile for addSub. Automatically generated by SBV. Do not edit!
-- > 
-- > # include any user-defined .mk file in the current directory.
-- > -include *.mk
-- > 
-- > CC=gcc
-- > CCFLAGS?=-Wall -O3 -DNDEBUG -fomit-frame-pointer
-- > 
-- > all: addSub_driver
-- > 
-- > addSub.o: addSub.c addSub.h
-- > 	${CC} ${CCFLAGS} -c $< -o $@
-- > 
-- > addSub_driver.o: addSub_driver.c
-- > 	${CC} ${CCFLAGS} -c $< -o $@
-- > 
-- > addSub_driver: addSub.o addSub_driver.o
-- > 	${CC} ${CCFLAGS} $^ -o $@
-- > 
-- > clean:
-- > 	rm -f *.o
-- > 
-- > veryclean: clean
-- > 	rm -f addSub_driver
--
-- File: @addSub.h@
--
-- > /* Header file for addSub. Automatically generated by SBV. Do not edit! */
-- > 
-- > #ifndef __addSub__HEADER_INCLUDED__
-- > #define __addSub__HEADER_INCLUDED__
-- > 
-- > #include <inttypes.h>
-- > #include <stdint.h>
-- > 
-- > /* Unsigned bit-vectors */
-- > typedef uint8_t  SBool  ;
-- > typedef uint8_t  SWord8 ;
-- > typedef uint16_t SWord16;
-- > typedef uint32_t SWord32;
-- > typedef uint64_t SWord64;
-- > 
-- > /* Signed bit-vectors */
-- > typedef int8_t  SInt8 ;
-- > typedef int16_t SInt16;
-- > typedef int32_t SInt32;
-- > typedef int64_t SInt64;
-- > 
-- > /* Entry point prototype: */
-- > void addSub(const SWord8 x, const SWord8 y, SWord8 *sum,
-- >             SWord8 *dif);
-- > 
-- > #endif /* __addSub__HEADER_INCLUDED__ */
--
-- File: @addSub.c@
--
-- > /* File: "addSub.c". Automatically generated by SBV. Do not edit! */
-- > 
-- > #include <inttypes.h>
-- > #include <stdint.h>
-- > #include "addSub.h"
-- > 
-- > void addSub(const SWord8 x, const SWord8 y, SWord8 *sum,
-- >             SWord8 *dif)
-- > {
-- >   const SWord8 s0 = x;
-- >   const SWord8 s1 = y;
-- >   const SWord8 s2 = s0 + s1;
-- >   const SWord8 s3 = s0 - s1;
-- >   
-- >   *sum = s2;
-- >   *dif = s3;
-- > }
--
-- File: @addSub_driver.c@
--
-- > /* Example driver program for addSub. */
-- > /* Automatically generated by SBV. Edit as you see fit! */
-- > 
-- > #include <inttypes.h>
-- > #include <stdint.h>
-- > #include <stdio.h>
-- > #include "addSub.h"
-- > 
-- > int main(void)
-- > {
-- >   SWord8 sum;
-- >   SWord8 dif;
-- >   
-- >   addSub(132, 241, &sum, &dif);
-- >   
-- >   printf("addSub(132, 241, &sum, &dif) ->\n");
-- >   printf("  sum = %"PRIu8"\n", sum);
-- >   printf("  dif = %"PRIu8"\n", dif);
-- >   
-- >   return 0;
-- > }
--
genAddSub :: IO ()
genAddSub = compileToC (Just "xx") "addSub" $ do
        x <- cgInput "x"
        y <- cgInput "y"
        let (s, d) = addSub x y
        cgOutput "sum" s
        cgOutput "dif" d

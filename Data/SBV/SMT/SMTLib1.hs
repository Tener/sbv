-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.SMT.SMTLib1
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- Conversion of symbolic programs to SMTLib format, Using v1 of the standard
-----------------------------------------------------------------------------
{-# LANGUAGE PatternGuards #-}

module Data.SBV.SMT.SMTLib1(cvt, addNonEqConstraints) where

import qualified Data.Foldable as F (toList)
import Data.List  (intercalate)
import Data.Maybe (fromMaybe)

import Data.SBV.BitVectors.Data

addNonEqConstraints :: [[(String, CW)]] -> SMTLibPgm -> Maybe String
addNonEqConstraints nonEqConstraints (SMTLibPgm _ (aliasTable, pre, post)) = Just $ intercalate "\n" $
     pre
  ++ [ " ; --- refuted-models ---" ]
  ++ concatMap nonEqs (map (map intName) nonEqConstraints)
  ++ post
 where intName (s, c)
          | Just sw <- s `lookup` aliasTable = (show sw, c)
          | True                             = (s, c)

nonEqs :: [(String, CW)] -> [String]
nonEqs []     =  []
nonEqs [sc]   =  [" :assumption " ++ nonEq sc]
nonEqs (sc:r) =  [" :assumption (or " ++ nonEq sc]
              ++ map (("                 " ++) . nonEq) r
              ++ ["             )"]

nonEq :: (String, CW) -> String
nonEq (s, c) = "(not (= " ++ s ++ " " ++ cvtCW c ++ "))"

cvt :: Bool                                        -- ^ has infinite precision values
    -> Bool                                        -- ^ is this a sat problem?
    -> [String]                                    -- ^ extra comments to place on top
    -> [(Quantifier, NamedSymVar)]                 -- ^ inputs
    -> [Either SW (SW, [SW])]                      -- ^ skolemized version of the inputs
    -> [(SW, CW)]                                  -- ^ constants
    -> [((Int, (Bool, Size), (Bool, Size)), [SW])] -- ^ auto-generated tables
    -> [(Int, ArrayInfo)]                          -- ^ user specified arrays
    -> [(String, SBVType)]                         -- ^ uninterpreted functions/constants
    -> [(String, [String])]                        -- ^ user given axioms
    -> Pgm                                         -- ^ assignments
    -> SW                                          -- ^ output variable
    -> ([String], [String])
cvt hasInf isSat comments qinps _skolemInps consts tbls arrs uis axs asgnsSeq out
  | hasInf
  = error "SBV: The chosen solver does not support infinite precision values. (Use z3 instead.)"
  | not ((isSat && allExistential) || (not isSat && allUniversal))
  = error "SBV: The chosen solver does not support quantified variables. (Use z3 instead.)"
  | True
  = (pre, post)
  where quantifiers    = map fst qinps
        allExistential = all (== EX)  quantifiers
        allUniversal   = all (== ALL) quantifiers
        logic
         | null tbls && null arrs && null uis = "QF_BV"
         | True                               = "QF_AUFBV"
        inps = map (fst . snd) qinps
        pre =    [ "; Automatically generated by SBV. Do not edit." ]
              ++ map ("; " ++) comments
              ++ ["(benchmark sbv"
                 , " :logic " ++ logic
                 , " :status unknown"
                 , " ; --- inputs ---"
                 ]
              ++ map decl inps
              ++ [ " ; --- declarations ---" ]
              ++ map (decl . fst) consts
              ++ map (decl . fst) asgns
              ++ [ " ; --- constants ---" ]
              ++ map cvtCnst consts
              ++ [ " ; --- tables ---" ]
              ++ concatMap mkTable tbls
              ++ [ " ; --- arrays ---" ]
              ++ concatMap declArray arrs
              ++ [ " ; --- uninterpreted constants ---" ]
              ++ concatMap declUI uis
              ++ [ " ; --- user given axioms ---" ]
              ++ map declAx axs
              ++ [ " ; --- assignments ---" ]
              ++ map cvtAsgn asgns
        post =    [ " ; --- formula ---" ]
               ++ [mkFormula isSat out]
               ++ [")"]
        asgns = F.toList asgnsSeq

-- TODO: Does this work for SMT-Lib when the index/element types are signed?
-- Currently we ignore the signedness of the arguments, as there appears to be no way
-- to capture that in SMT-Lib; and likely it does not matter. Would be good to check
-- explicitly though.
mkTable :: ((Int, (Bool, Size), (Bool, Size)), [SW]) -> [String]
mkTable ((i, (_, atSz), (_, rtSz)), elts) = (" :extrafuns ((" ++ t ++ " Array[" ++ show at ++ ":" ++ show rt ++ "]))") : zipWith mkElt elts [(0::Int)..]
  where t = "table" ++ show i
        mkElt x k = " :assumption (= (select " ++ t ++ " bv" ++ show k ++ "[" ++ show at ++ "]) " ++ show x ++ ")"
        at = fromMaybe (die "Unbounded integers") (unSize atSz)
        rt = fromMaybe (die "Unbounded integers") (unSize rtSz)

-- Unexpected input, or things we will probably never support
die :: String -> a
die msg = error $ "SBV->SMTLib1: Unexpected: " ++ msg

declArray :: (Int, ArrayInfo) -> [String]
declArray (i, (_, ((_, atSz), (_, rtSz)), ctx)) = adecl : ctxInfo
  where nm = "array_" ++ show i
        adecl = " :extrafuns ((" ++ nm ++ " Array[" ++ show at ++ ":" ++ show rt ++ "]))"
        at = fromMaybe (die "Unbounded integers") (unSize atSz)
        rt = fromMaybe (die "Unbounded integers") (unSize rtSz)
        ctxInfo = case ctx of
                    ArrayFree Nothing   -> []
                    ArrayFree (Just sw) -> declA sw
                    ArrayReset _ sw     -> declA sw
                    ArrayMutate j a b -> [" :assumption (= " ++ nm ++ " (store array_" ++ show j ++ " " ++ show a ++ " " ++ show b ++ "))"]
                    ArrayMerge  t j k -> [" :assumption (= " ++ nm ++ " (ite (= bv1[1] " ++ show t ++ ") array_" ++ show j ++ " array_" ++ show k ++ "))"]
        declA sw = let iv = nm ++ "_freeInitializer"
                   in [ " :extrafuns ((" ++ iv ++ " BitVec[" ++ show at ++ "]))"
                      , " :assumption (= (select " ++ nm ++ " " ++ iv ++ ") " ++ show sw ++ ")"
                      ]

declAx :: (String, [String]) -> String
declAx (nm, ls) = (" ;; -- user given axiom: " ++ nm ++ "\n   ") ++ intercalate "\n   " ls

declUI :: (String, SBVType) -> [String]
declUI (i, t) = [" :extrafuns ((uninterpreted_" ++ i ++ " " ++ cvtType t ++ "))"]

mkFormula :: Bool -> SW -> String
mkFormula isSat s
 | isSat = " :formula (= " ++ show s ++ " bv1[1])"
 | True  = " :formula (= " ++ show s ++ " bv0[1])"

-- SMTLib represents signed/unsigned quantities with the same type
decl :: SW -> String
decl s = " :extrafuns  ((" ++ show s ++ " BitVec[" ++ show (intSizeOf s) ++ "]))"

cvtAsgn :: (SW, SBVExpr) -> String
cvtAsgn (s, e) = " :assumption (= " ++ show s ++ " " ++ cvtExp e ++ ")"

cvtCnst :: (SW, CW) -> String
cvtCnst (s, c) = " :assumption (= " ++ show s ++ " " ++ cvtCW c ++ ")"

cvtCW :: CW -> String
cvtCW x | not (hasSign x) = "bv" ++ show (cwVal x) ++ "[" ++ show (intSizeOf x) ++ "]"
-- signed numbers (with 2's complement representation) is problematic
-- since there's no way to put a bvneg over a positive number to get minBound..
-- Hence, we punt and use binary notation in that particular case
cvtCW x | cwVal x == least = mkMinBound (intSizeOf x)
  where least = negate (2 ^ intSizeOf x)
cvtCW x = negIf (w < 0) $ "bv" ++ show (abs w) ++ "[" ++ show (intSizeOf x) ++ "]"
  where w = cwVal x

negIf :: Bool -> String -> String
negIf True  a = "(bvneg " ++ a ++ ")"
negIf False a = a

-- anamoly at the 2's complement min value! Have to use binary notation here
-- as there is no positive value we can provide to make the bvneg work.. (see above)
mkMinBound :: Int -> String
mkMinBound i = "bv1" ++ replicate (i-1) '0' ++ "[" ++ show i ++ "]"

rot :: String -> Int -> SW -> String
rot o c x = "(" ++ o ++ "[" ++ show c ++ "] " ++ show x ++ ")"

shft :: String -> String -> Int -> SW -> String
shft oW oS c x= "(" ++ o ++ " " ++ show x ++ " " ++ cvtCW c' ++ ")"
   where s  = hasSign x
         c' = mkConstCW (s, sizeOf x) c
         o  = if hasSign x then oS else oW

cvtExp :: SBVExpr -> String
cvtExp (SBVApp Ite [a, b, c]) = "(ite (= bv1[1] " ++ show a ++ ") " ++ show b ++ " " ++ show c ++ ")"
cvtExp (SBVApp (Rol i) [a])   = rot "rotate_left"  i a
cvtExp (SBVApp (Ror i) [a])   = rot "rotate_right" i a
cvtExp (SBVApp (Shl i) [a])   = shft "bvshl"  "bvshl"  i a
cvtExp (SBVApp (Shr i) [a])   = shft "bvlshr" "bvashr" i a
cvtExp (SBVApp (LkUp (t, (_, atSz), _, l) i e) [])
  | needsCheck = "(ite " ++ cond ++ show e ++ " " ++ lkUp ++ ")"
  | True       = lkUp
  where at = fromMaybe (die "Unbounded integers") (unSize atSz)
        needsCheck = (2::Integer)^at > fromIntegral l
        lkUp = "(select table" ++ show t ++ " " ++ show i ++ ")"
        cond
         | hasSign i = "(or " ++ le0 ++ " " ++ gtl ++ ") "
         | True      = gtl ++ " "
        (less, leq) = if hasSign i then ("bvslt", "bvsle") else ("bvult", "bvule")
        mkCnst = cvtCW . mkConstCW (hasSign i, sizeOf i)
        le0  = "(" ++ less ++ " " ++ show i ++ " " ++ mkCnst 0 ++ ")"
        gtl  = "(" ++ leq  ++ " " ++ mkCnst l ++ " " ++ show i ++ ")"
cvtExp (SBVApp (Extract i j) [a]) = "(extract[" ++ show i ++ ":" ++ show j ++ "] " ++ show a ++ ")"
cvtExp (SBVApp (ArrEq i j) []) = "(ite (= array_" ++ show i ++ " array_" ++ show j ++") bv1[1] bv0[1])"
cvtExp (SBVApp (ArrRead i) [a]) = "(select array_" ++ show i ++ " " ++ show a ++ ")"
cvtExp (SBVApp (Uninterpreted nm) [])   = "uninterpreted_" ++ nm
cvtExp (SBVApp (Uninterpreted nm) args) = "(uninterpreted_" ++ nm ++ " " ++ unwords (map show args) ++ ")"
cvtExp inp@(SBVApp op args)
  | Just f <- lookup op smtOpTable
  = f (any hasSign args) (map show args)
  | True
  = error $ "SBV.SMT.SMTLib1.cvtExp: impossible happened; can't translate: " ++ show inp
  where lift2  o _ [x, y] = "(" ++ o ++ " " ++ x ++ " " ++ y ++ ")"
        lift2  o _ sbvs   = error $ "SBV.SMTLib1.cvtExp.lift2: Unexpected arguments: "   ++ show (o, sbvs)
        lift2B oU oS sgn sbvs = "(ite " ++ lift2S oU oS sgn sbvs ++ " bv1[1] bv0[1])"
        lift2S oU oS sgn sbvs
          | sgn
          = lift2 oS sgn sbvs
          | True
          = lift2 oU sgn sbvs
        lift2N o sgn sbvs = "(bvnot " ++ lift2 o sgn sbvs ++ ")"
        lift1  o _ [x]    = "(" ++ o ++ " " ++ x ++ ")"
        lift1  o _ sbvs   = error $ "SBV.SMT.SMTLib1.cvtExp.lift1: Unexpected arguments: "   ++ show (o, sbvs)
        smtOpTable = [ (Plus,          lift2   "bvadd")
                     , (Minus,         lift2   "bvsub")
                     , (Times,         lift2   "bvmul")
                     , (Quot,          lift2S  "bvudiv" "bvsdiv")
                     , (Rem,           lift2S  "bvurem" "bvsrem")
                     , (Equal,         lift2   "bvcomp")
                     , (NotEqual,      lift2N  "bvcomp")
                     , (LessThan,      lift2B  "bvult" "bvslt")
                     , (GreaterThan,   lift2B  "bvugt" "bvsgt")
                     , (LessEq,        lift2B  "bvule" "bvsle")
                     , (GreaterEq,     lift2B  "bvuge" "bvsge")
                     , (And,           lift2   "bvand")
                     , (Or,            lift2   "bvor")
                     , (XOr,           lift2   "bvxor")
                     , (Not,           lift1   "bvnot")
                     , (Join,          lift2   "concat")
                     ]

cvtType :: SBVType -> String
cvtType (SBVType []) = error "SBV.SMT.SMTLib1.cvtType: internal: received an empty type!"
cvtType (SBVType xs) = unwords $ map sh xs
  where sh (_, Size Nothing)  = die "unbounded Integer"
        sh (_, Size (Just s)) = "BitVec[" ++ show s ++ "]"

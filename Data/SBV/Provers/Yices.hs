-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.Provers.Yices
-- Copyright   :  (c) Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
-- Portability :  portable
--
-- The connection to the Yices SMT solver
-----------------------------------------------------------------------------

{-# LANGUAGE PatternGuards #-}

module Data.SBV.Provers.Yices(yices, timeout) where

import Data.Char          (isDigit)
import Data.List          (sortBy, isPrefixOf, intercalate)
import Data.Maybe         (catMaybes)
import System.Environment (getEnv)

import Data.SBV.BitVectors.Data
import Data.SBV.Provers.SExpr
import Data.SBV.SMT.SMT

-- | The description of the Yices SMT solver
-- The default executable is @\"yices\"@, which must be in your path. You can use the @SBV_YICES@ environment variable to point to the executable on your system.
-- The default options are @\"-m -f\"@, which is valid for Yices 2 series. You can use the @SBV_YICES_OPTIONS@ environment variable to override the options.
yices :: SMTSolver
yices = SMTSolver {
           name       = "Yices"
         , executable = "yices"
         -- , options    = ["-tc", "-smt", "-e"]   -- For Yices1
         , options    = ["-m", "-f"]  -- For Yices2
         , engine     = \cfg inps pgm -> do
                                execName <-                getEnv "SBV_YICES"           `catch` (\_ -> return (executable (solver cfg)))
                                execOpts <- (words `fmap` (getEnv "SBV_YICES_OPTIONS")) `catch` (\_ -> return (options (solver cfg)))
                                let cfg' = cfg { solver = (solver cfg) {executable = execName, options = execOpts} }
                                standardSolver cfg' pgm (ProofError cfg) (interpret cfg inps)
         }

timeout :: Int -> SMTSolver -> SMTSolver
timeout n s
  | n <= 0 = error $ "Yices.timeout value should be > 0, received: " ++ show n
  | True   = s{options = options s ++ ["-t", show n]}

sortByNodeId :: [(Int, a)] -> [(Int, a)]
sortByNodeId = sortBy (\(x, _) (y, _) -> compare x y)

interpret :: SMTConfig -> [NamedSymVar] -> [String] -> SMTResult
interpret cfg _    ("unsat":_)      = Unsatisfiable cfg
interpret cfg inps ("unknown":rest) = Unknown       cfg  $ extractMap inps rest
interpret cfg inps ("sat":rest)     = Satisfiable   cfg  $ extractMap inps rest
interpret cfg _    ("timeout":_)    = TimeOut       cfg
interpret cfg _    ls               = ProofError    cfg  $ ls

extractMap :: [NamedSymVar] -> [String] -> SMTModel
extractMap inps solverLines =
   SMTModel { modelAssocs    = map (\(_, y) -> y) $ sortByNodeId $ concatMap (getCounterExample inps) modelLines
            , modelUninterps = [(n, ls) | (UFun, n, ls) <- uis]
            , modelArrays    = [(n, ls) | (UArr, n, ls) <- uis]
            } 
  where (modelLines, unintLines) = break ("--- " `isPrefixOf`) solverLines
        uis = extractUnints unintLines

getCounterExample :: [NamedSymVar] -> String -> [(Int, (String, CW))]
getCounterExample inps line = either err extract (parseSExpr line)
  where err r =  error $  "*** Failed to parse Yices model output from: "
                       ++ "*** " ++ show line ++ "\n"
                       ++ "*** Reason: " ++ r ++ "\n"
        isInput ('s':v)
          | all isDigit v = let inpId :: Int
                                inpId = read v
                            in case [(s, nm) | (s@(SW _ (NodeId n)), nm) <-  inps, n == inpId] of
                                 []        -> Nothing
                                 [(s, nm)] -> Just (inpId, s, nm)
                                 matches -> error $  "SBV.Yices: Cannot uniquely identify value for "
                                                  ++ 's':v ++ " in "  ++ show matches
        isInput _       = Nothing
        extract (S_App [S_Con "=", S_Con v, S_Num i]) | Just (n, s, nm) <- isInput v = [(n, (nm, mkConstCW (hasSign s, sizeOf s) i))]
        extract (S_App [S_Con "=", S_Num i, S_Con v]) | Just (n, s, nm) <- isInput v = [(n, (nm, mkConstCW (hasSign s, sizeOf s) i))]
        extract _                                                                    = []

extractUnints :: [String] -> [(UnintKind, String, [String])]
extractUnints = catMaybes . map extractUnint . chunks
  where chunks []     = []
        chunks (x:xs) = let (f, r) = span (not . ("---" `isPrefixOf`)) xs in (x:f) : chunks r

data UnintKind = UFun | UArr deriving Eq

-- Parsing the Yices output is done extremely crudely and designed
-- mostly by observation of Yices output. Likely to have bugs and
-- brittle as Yices evolves. We really need an SMT-Lib2 like interface.
extractUnint :: [String] -> Maybe (UnintKind, String, [String])
extractUnint []           = Nothing
extractUnint (tag : rest)
  | null tag'             = Nothing
  | True                  = mapM (getUIVal knd f') rest >>= \xs -> return (knd, f', xs)
  where knd | "--- uninterpreted_" `isPrefixOf` tag = UFun
            | True                                  = UArr
        tag' = dropWhile (/= '_') tag
        f    = takeWhile (/= ' ') (tail tag')
        f'   = case knd of
                UArr -> "array_" ++ f
                _    -> f

getUIVal :: UnintKind -> String -> String -> Maybe String
getUIVal knd f s
  | "default: " `isPrefixOf` s
  = getDefaultVal knd f (dropWhile (/= ' ') s)
  | True
  = case parseSExpr s of
       Right (S_App [S_Con "=", (S_App (S_Con _ : args)), S_Num i]) -> getCallVal knd f args i
       _ -> Nothing

getDefaultVal :: UnintKind -> String -> String -> Maybe String
getDefaultVal knd f n = case parseSExpr n of
                         Right (S_Num i) -> Just $ showDefault knd f (show i)
                         _               -> Nothing

getCallVal :: UnintKind -> String -> [SExpr] -> Integer -> Maybe String
getCallVal knd f args res = mapM getArg args >>= \as -> return (showCall knd f as (show res))

getArg :: SExpr -> Maybe String
getArg (S_Num i) = Just (show i)
getArg _         = Nothing

showDefault :: UnintKind -> String -> String -> String
showDefault UFun f res = f ++ " _ = "  ++ res
showDefault UArr f res = f ++ "[_] = " ++ res

showCall :: UnintKind -> String -> [String] -> String -> String
showCall UFun f as res = f ++ " " ++ unwords as ++ " = " ++ res
showCall UArr f as res = f ++ "[" ++ intercalate ", " as ++ "]" ++ " = " ++ res

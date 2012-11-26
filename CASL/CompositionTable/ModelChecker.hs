{- |
Module      :  $Header$
Description :  checks validity of models regarding a composition table
Copyright   :  (c) Uni Bremen 2005
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  fmossa@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable

checks validity of models regarding a composition table
-}

module CASL.CompositionTable.ModelChecker (modelCheck) where

import CASL.CompositionTable.CompositionTable
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.ToDoc
import CASL.Logic_CASL
import Logic.Logic

import Common.AS_Annotation
import Common.Result
import Common.Id
import Common.DocUtils
import qualified Common.Lib.MapSet as MapSet

import qualified Data.Set as Set
import qualified Data.Map as Map
import Data.Maybe
import Data.List

modelCheck :: Int -> (Sign () (), [Named (FORMULA ())])
           -> Table -> Result ()
modelCheck c (sign, sent) t1 = do
  let t = toTable2 t1
  mapM_ (modelCheckTest c (extractAnnotations (annoMap sign)) sign t) sent

data Table2 = Table2 Baserel BSet [CmpEntry] Conversetable

data CmpEntry = CmpEntry Baserel Baserel BSet

toTable2 :: Table -> Table2
toTable2 (Table (Table_Attrs _ id_ baserels)
  (Compositiontable comptbl) convtbl _ _) =
  Table2 id_ (Set.fromList baserels) (map toCmpEntry comptbl) convtbl

toCmpEntry :: Cmptabentry -> CmpEntry
toCmpEntry (Cmptabentry (Cmptabentry_Attrs rel1 rel2) baserels) =
  CmpEntry rel1 rel2 $ Set.fromList baserels

extractAnnotations :: MapSet.MapSet Symbol Annotation -> [(OP_SYMB, String)]
extractAnnotations m =
    catMaybes [extractAnnotation (a, b) | (a, b) <- MapSet.toList m]

extractAnnotation :: (Symbol, [Annotation]) -> Maybe (OP_SYMB, String)
extractAnnotation (Symbol symbname symbtype, set) = case symbtype of
    OpAsItemType _ -> Just (createOpSymb symbname symbtype, getAnno set)
    _ -> Nothing

createOpSymb :: Id -> SymbType -> OP_SYMB
createOpSymb i st = case st of
  OpAsItemType ty -> Qual_op_name i (toOP_TYPE ty) nullRange
  _ -> error "CASL.CompositionTable.ModelChecker.createOpSymb"

getAnno :: [Annotation] -> String
getAnno as = case as of
   [a] -> getAnnoAux a
   _ -> "failure"

getAnnoAux :: Annotation -> String
getAnnoAux a = case a of
    Unparsed_anno (Annote_word word) _ _ -> word
    _ -> ""

showDiagStrings :: [Diagnosis] -> String
showDiagStrings = intercalate "\n" . map diagString

modelCheckTest :: Int -> [(OP_SYMB, String)] -> Sign () () -> Table2
  -> Named (FORMULA ()) -> Result ()
modelCheckTest c symbs sign t x = let
    Result d _ = modelCheckTest1 (sign, x) t symbs
    n = length d
    fstr = shows (printTheoryFormula (mapNamed (simplify_sen CASL sign) x)) "\n"
      in if null d
      then hint () ("Formula succeeded:\n" ++ fstr) nullRange
      else warning () ("Formula failed:\n" ++ fstr ++ show n
               ++ " counter example" ++ (if n > 1 then "s" else "")
               ++ ":\n" ++ showDiagStrings (take c d)) nullRange

modelCheckTest1 :: (Sign () (), Named (FORMULA ())) -> Table2
                -> [(OP_SYMB, String)] -> Result Bool
modelCheckTest1 (sign, nSen) t symbs =
  let varass = Map.empty in case sentence nSen of
    Junction j formulas range -> let
        bs = map (\ f -> calculateFormula (sign, f) varass t symbs)
             formulas
        res = if j == Con then and else or
        in if res bs then return True else
            warning False (show j ++ "junction does not hold:"
                                 ++ showDoc (map (simplify_sen CASL sign)
                                 formulas) "") range
    f@(Relation f1 c f2 range) ->
                  let test1 = calculateFormula (sign, f1) varass t symbs
                      test2 = calculateFormula (sign, f2) varass t symbs
                      res = not (test1 && not test2)
                  in if if c == Equivalence then test1 == test2 else res
                     then return True
                     else warning False ("Relation does not hold: " ++
                          showDoc (simplify_sen CASL sign f) "") range
    Negation f range ->
                  let res = calculateFormula (sign, f) varass t symbs
                  in if not res then return True
                    else warning False
                                        ("Negation does not hold:"
                                        ++ showDoc (simplify_sen CASL
                                                   sign f) "") range
    Atom b range -> if b then return True else
      warning False "False-atom can't be fulfilled!" range
    Equation t1 Strong t2 range ->
                  let res1 = calculateTerm (sign, t1) varass t symbs
                      res2 = calculateTerm (sign, t2) varass t symbs
                  in if res1 == res2 then return True
                     else warning False
                       ("Strong Equation does not hold term1: "
                        ++ showDoc t1 "term2: " ++ showDoc t2 "") range
    qf@(Quantification _ decl _ _) ->
        let ass = generateVariableAssignments decl t
        in calculateQuantification (sign, qf)
                  ass t symbs
    e -> error $ "CASL.CompositionTable.ModelChecker.modelCheckTest1 "
         ++ showDoc e ""

calculateQuantification :: (Sign () (), FORMULA ()) -> [Assignment]
                        -> Table2 -> [(OP_SYMB, String)] -> Result Bool
calculateQuantification (sign, qf) vardecls t symbs = case qf of
    Quantification quant _ f range ->
        let tuples = map ( \ ass -> let
                res = calculateFormula (sign, f) ass t symbs
                in if res then (res, "") else (res, ' ' : showAssignments ass))
              vardecls
        in case quant of
        Universal -> let failedtuples = filter (not . fst) tuples
          in if null failedtuples then return True else do
             mapM_ (\ (_, msg) -> warning () msg range) failedtuples
             return False
        Existential -> let suceededTuples = filter fst tuples
          in if not (null suceededTuples) then return True else
               warning False "Existential not fulfilled" range
        Unique_existential ->
          let suceededTuples = take 2 $ filter fst tuples in
          case suceededTuples of
            [_] -> return True
            _ -> warning False "Unique Existential not fulifilled" range
    _ -> error "CASL.CompositionTable.ModelChecker.calculateQuantification"

type Assignment = Map.Map VAR Baserel

showAssignments :: Map.Map VAR Baserel -> String
showAssignments xs =
    '[' : intercalate ", " (map showSingleAssignment $ Map.toList xs) ++ "]"

showSingleAssignment :: (VAR, Baserel) -> String
showSingleAssignment (v, Baserel b) = show v ++ "->" ++ b

type BSet = Set.Set Baserel

calculateTerm :: (Sign () (), TERM ()) -> Assignment -> Table2
              -> [(OP_SYMB, String)] -> BSet
calculateTerm (sign, trm) ass t symbs = case trm of
    Qual_var var _ _ -> getBaseRelForVariable var ass
    Application opSymb terms _ ->
              applyOperation (getIdentifierForSymb opSymb symbs) (sign, terms)
              t ass symbs
    Sorted_term term _ _ -> calculateTerm (sign, term) ass t symbs
    Cast {} -> error "CASL.CompositionTable.ModelChecker.calculateTerm"
    Conditional t1 fo t2 _ ->
              let res = calculateFormula (sign, fo) ass t symbs
              in if res then calculateTerm (sign, t1) ass t symbs
                 else calculateTerm (sign, t2) ass t symbs
    _ -> Set.empty

getIdentifierForSymb :: OP_SYMB -> [(OP_SYMB, String)] -> String
getIdentifierForSymb symb = concatMap (getIdentifierForSymbAtomar symb)

getIdentifierForSymbAtomar :: OP_SYMB -> (OP_SYMB, String) -> String
getIdentifierForSymbAtomar symb (symb2, s) = if symb == symb2 then s else ""

applyOperation :: String -> (Sign () (), [TERM ()]) -> Table2
               -> Assignment -> [(OP_SYMB, String)] -> BSet
applyOperation ra (sign, ts) table@(Table2 _ baserels cmpentries convtbl)
  ass symbs = case ts of
    ft : rt -> let r1 = calculateTerm (sign, ft) ass table symbs
      in case rt of
         sd : _ | elem ra ["RA_composition", "RA_intersection", "RA_union"]
           -> let r2 = calculateTerm (sign, sd) ass table symbs
            in case ra of
               "RA_composition" -> calculateComposition cmpentries r1 r2
               "RA_intersection" -> Set.intersection r1 r2
               _ -> Set.union r1 r2
         _ -> case ra of
           "RA_complement" -> Set.difference baserels r1
           "RA_converse" -> calculateConverse convtbl r1
           _ -> case convtbl of
             Conversetable_Ternary inv shortc hom
               | elem ra ["RA_shortcut", "RA_inverse", "RA_homing"] ->
                  calculateConverseTernary (case ra of
               "RA_shortcut" -> shortc
               "RA_inverse" -> inv
               _ -> hom) r1
             _ -> defOp ra table
    _ -> defOp ra table

defOp :: String -> Table2 -> BSet
defOp ra (Table2 id_ baserels _ _) = case ra of
  "RA_one" -> baserels
  "RA_identity" -> Set.singleton id_
  _ -> Set.empty

calculateComposition :: [CmpEntry] -> BSet -> BSet -> BSet
calculateComposition entries rels1 rels2 =
    foldl' (\ rs (CmpEntry rel1 rel2 bs) ->
                    if Set.member rel1 rels1 && Set.member rel2 rels2
                    then Set.union bs rs else rs) Set.empty entries

calculateConverse :: Conversetable -> BSet -> BSet
calculateConverse (Conversetable_Ternary {}) _ = Set.empty
calculateConverse (Conversetable centries) rels =
    Set.unions $ map (calculateConverseAtomar rels) centries

calculateConverseAtomar :: BSet -> Contabentry -> BSet
calculateConverseAtomar rels (Contabentry rel1 rel2) =
   Set.unions [Set.fromList rel2 | Set.member rel1 rels]

calculateConverseTernary :: [Contabentry_Ternary] -> BSet -> BSet
calculateConverseTernary entries rels =
    Set.unions $ map (calculateConverseTernaryAtomar rels) entries

calculateConverseTernaryAtomar :: BSet -> Contabentry_Ternary -> BSet
calculateConverseTernaryAtomar rels2 (Contabentry_Ternary rel1 rels1) =
  if Set.member rel1 rels2 then Set.fromList rels1 else Set.empty

getBaseRelForVariable :: VAR -> Assignment -> BSet
getBaseRelForVariable var = maybe Set.empty Set.singleton . Map.lookup var

calculateFormula :: (Sign () (), FORMULA ()) -> Assignment -> Table2
                 -> [(OP_SYMB, String)] -> Bool
calculateFormula (sign, qf) varass t symbs = case qf of
    Quantification _ vardecls _ _ ->
                 let Result _ res = calculateQuantification (sign, qf)
                                       (appendVariableAssignments
                                       varass vardecls t) t symbs
                 in res == Just True
    Junction j formulas _ -> (if j == Con then and else or)
        [calculateFormula (sign, x) varass t symbs | x <- formulas]
    Relation f1 c f2 _ ->
                 let test1 = calculateFormula (sign, f1) varass t symbs
                     test2 = calculateFormula (sign, f2) varass t symbs
                 in if c == Equivalence then test1 == test2 else
                        not (test1 && not test2)
    Negation f _ -> not (calculateFormula (sign, f) varass t symbs)
    Atom b _ -> b
    Equation term1 Strong term2 _ ->
                 let t1 = calculateTerm (sign, term1) varass t symbs
                     t2 = calculateTerm (sign, term2) varass t symbs
                 in t1 == t2
    _ -> error $ "CASL.CompositionTable.ModelChecker.calculateFormula "
         ++ showDoc qf ""

generateVariableAssignments :: [VAR_DECL] -> Table2 -> [Assignment]
generateVariableAssignments vardecls =
  let vs = Set.fromList $ getVars vardecls in
  gVAs vs . Set.toList . getBaseRelations

gVAs :: Set.Set VAR -> [Baserel] -> [Map.Map VAR Baserel]
gVAs vs brs = Set.fold (\ v rs -> [Map.insert v b r | b <- brs, r <- rs])
  [Map.empty] vs

getVars :: [VAR_DECL] -> [VAR]
getVars = concatMap getVarsAtomic

getVarsAtomic :: VAR_DECL -> [VAR]
getVarsAtomic (Var_decl vars _ _) = vars

getBaseRelations :: Table2 -> BSet
getBaseRelations (Table2 _ br _ _) = br

appendVariableAssignments :: Assignment -> [VAR_DECL] -> Table2 -> [Assignment]
appendVariableAssignments vars decls t =
     map (Map.union vars) (generateVariableAssignments decls t)

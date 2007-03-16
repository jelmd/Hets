{-# OPTIONS -fallow-undecidable-instances #-}
{- |
Module      :  $Header$
Description :  Instance of class Logic for propositional logic
Copyright   :  (c) Dominik Luecke, Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@tzi.de
Stability   :  experimental
Portability :  non-portable (imports Logic.Logic)

Sublogics for Propositional Logic
-}

{-
  Ref.

  http://en.wikipedia.org/wiki/Propositional_logic

  Till Mossakowski, Joseph Goguen, Razvan Diaconescu, Andrzej Tarlecki.
  What is a Logic?.
  In Jean-Yves Beziau (Ed.), Logica Universalis, pp. 113-@133. Birkhäuser.
  2005.
-}

module Propositional.Sublogic
    (
     sl_basic_spec                  -- determine sublogic for basic spec
    , PropFormulae (..)             -- types of propositional formulae
    , PropSL (..)                   -- sublogics for propositional logic
    , sublogics_max                 -- join of sublogics
    , top                           -- Propositional
    , bottom                        -- CNF
    , sublogics_all                 -- all sublogics
    , sublogics_name                -- name of sublogics
    , sl_sig                        -- sublogic for a signature
    , sl_form                       -- sublogic for a formula
    , sl_sym                        -- sublogic for symbols
    , sl_symit                      -- sublogic for symbol items
    , sl_mor                        -- sublogic for morphisms
    , sl_symmap                     -- sublogic for symbol map items
    , prSymbolM                     -- projection of symbols
    , prSig                         -- projections of signatures
    , prMor                         -- projections of morphisms
    , prSymMapM                     -- projections of symbol maps
    , prSymM                        -- projections of SYMB_ITEMS
    , prFormulaM                    -- projections of formulae 
    , prBasicSpec                   -- projections of basic specs
    , isPropIE
    , isPropI
    , isPropE
    , isProp
    , isHC
    , isCNF
    )
    where

import qualified Propositional.Tools as Tools
import qualified Propositional.AS_BASIC_Propositional as AS_BASIC
import qualified Common.AS_Annotation as AS_Anno
import qualified Propositional.Sign as Sign
import qualified Propositional.Symbol as Symbol
import qualified Propositional.Morphism as Morphism
import Common.Lib.State

class (Eq l, Show l) => Lattice l where
  cjoin :: l -> l -> l
  ctop :: l
  bot :: l

instance Lattice () where
  cjoin _ _ = ()
  ctop = ()
  bot = ()

instance Lattice Bool where
  cjoin = (||)
  ctop = True
  bot = False

-------------------------------------------------------------------------------
-- datatyper                                                                 --
-------------------------------------------------------------------------------

-- | types of propositional formulae
data PropFormulae = PlainFormula      -- Formula without structural constraints
                  | CNF               -- CNF (implies restriction on ops)
                  | HornClause        -- Horn Clause Formulae
                  deriving (Show, Eq, Ord)

-- | sublogics for propositional logic
data PropSL = PropSL
    {
      format       :: PropFormulae     -- Structural restrictions
    , has_imp      :: Bool             -- Implication ?
    , has_equiv    :: Bool             -- Equivalence ?
    } deriving (Show, Eq)

-- | Check for particular sublogics
isPropIE :: PropSL -> Bool
isPropIE sl = format sl == PlainFormula && has_equiv sl && has_imp sl

isPropI :: PropSL -> Bool
isPropI sl = format sl == PlainFormula && not ( has_equiv sl ) && has_imp sl

isPropE :: PropSL -> Bool
isPropE sl = format sl == PlainFormula && has_equiv sl && not ( has_imp sl )

isProp :: PropSL -> Bool
isProp sl = format sl == PlainFormula && 
            not ( has_equiv sl ) && 
            not ( has_imp sl )

isCNF :: PropSL -> Bool
isCNF sl = format sl == CNF && 
            not ( has_equiv sl ) && 
            not ( has_imp sl )

isHC :: PropSL -> Bool
isHC sl = format sl == HornClause && 
            not ( has_equiv sl ) && 
            not ( has_imp sl )

-- | comparison of sublogics
compareLE :: PropSL -> PropSL -> Bool
compareLE sl1 sl2 = bothHC || bothCNF || pfLE
    where 
      form1   = format sl1
      form2   = format sl2
      i1      = has_imp sl1
      i2      = has_imp sl2
      e1      = has_equiv sl1
      e2      = has_equiv sl2
      bothHC = (form1 == form2) && (form1 == HornClause)
      bothCNF = (form1 == form2) && (form1 == CNF)
      pfLE    = (not bothCNF) && (i1 <= i2) && (e1 <= e2)

------------------------------------------------------------------------------
-- Special elements in the Lattice of logics                                --
------------------------------------------------------------------------------

top :: PropSL
top = PropSL PlainFormula True True

bottom :: PropSL
bottom = PropSL HornClause False False 

need_PF :: PropSL
need_PF = bottom { format = PlainFormula }

need_imp :: PropSL
need_imp = bottom { has_imp = True }

need_equiv :: PropSL
need_equiv = bottom { has_equiv = True }

need_CNF :: PropSL
need_CNF   = bottom { format = CNF }

-------------------------------------------------------------------------------
-- join and max                                                              --
-------------------------------------------------------------------------------

sublogics_join :: (PropFormulae -> PropFormulae -> PropFormulae)
                  -> (Bool -> Bool -> Bool)
                  -> (Bool -> Bool -> Bool)
                  -> PropSL -> PropSL -> PropSL
sublogics_join pfF imF eqF a b = PropSL
                                 {
                                   format    = pfF (format a) (format b)
                                 , has_imp   = imF (has_imp a) (has_imp b)
                                 , has_equiv = eqF (has_equiv a) (has_equiv b) 
                                 }

joinType :: PropFormulae -> PropFormulae -> PropFormulae
joinType CNF CNF = CNF
joinType HornClause HornClause = HornClause
joinType HornClause CNF = CNF
joinType CNF HornClause = CNF
joinType _   _   = PlainFormula

sublogics_max :: PropSL -> PropSL -> PropSL
sublogics_max = sublogics_join joinType max max 

-------------------------------------------------------------------------------
-- Helpers                                                                   --
-------------------------------------------------------------------------------

-- compute sublogics from a list of sublogics
--
comp_list :: [PropSL] -> PropSL
comp_list l = foldl sublogics_max bottom l

------------------------------------------------------------------------------
-- Functions to compute minimal sublogic for a given element, these work    --
-- by recursing into all subelements                                        --
------------------------------------------------------------------------------

-- | determines the sublogic for symbol map items
sl_symmap :: PropSL -> AS_BASIC.SYMB_MAP_ITEMS -> PropSL
sl_symmap ps _ = ps

-- | determines the sublogic for a morphism
sl_mor :: PropSL -> Morphism.Morphism -> PropSL
sl_mor ps _ = ps

-- | determines the sublogic for a Signature
sl_sig :: PropSL -> Sign.Sign -> PropSL
sl_sig ps _ = ps

-- | determines the sublogic for Symbol items
sl_symit :: PropSL -> AS_BASIC.SYMB_ITEMS  -> PropSL
sl_symit ps _ = ps

-- | determines the sublogic for symbols
sl_sym :: PropSL -> Symbol.Symbol -> PropSL
sl_sym ps _ = ps

-- | determines sublogic for formula
sl_form :: PropSL -> AS_BASIC.FORMULA -> PropSL
sl_form ps f = sl_fl_form ps $ Tools.flatten f

-- | determines sublogic for flattened formula
sl_fl_form :: PropSL -> [AS_BASIC.FORMULA] -> PropSL
sl_fl_form ps f = foldl (sublogics_max) ps $ map (\x -> evalState (ana_form ps x) 0) f 

-- analysis of single "clauses"
ana_form :: PropSL -> AS_BASIC.FORMULA -> State Int PropSL
ana_form ps f = 
    case f of
      AS_BASIC.Conjunction l _   -> 
          do 
            st <- get
            return $ sublogics_max need_PF 
                       (comp_list $ map (\x -> (evalState (ana_form ps x) (st + 1))) l) 
      AS_BASIC.Implication l m _ -> 
           do 
             st <- get
             return $ 
                    if st < 1 
                    then
                        if (format ps == HornClause) 
                        then
                            -- insert Horn Analysis
                            sublogics_max need_imp $ 
                            sublogics_max need_PF $
                            sublogics_max ((\x -> evalState (ana_form ps x) (st+1)) l)
                                              ((\x -> evalState (ana_form ps x) (st+1)) m)
                        else
                            sublogics_max need_imp $ 
                            sublogics_max need_PF $
                            sublogics_max ((\x -> evalState (ana_form ps x) (st+1)) l)
                                              ((\x -> evalState (ana_form ps x) (st+1)) m)
                    else
                        sublogics_max need_imp $ 
                        sublogics_max need_PF $
                        sublogics_max ((\x -> evalState (ana_form ps x) (st+1)) l)
                                          ((\x -> evalState (ana_form ps x) (st+1)) m)                    
      AS_BASIC.Equivalence l m _ -> 
           do 
             st <- get
             return $ sublogics_max need_equiv $ 
                    sublogics_max need_PF $
                    sublogics_max ((\x -> evalState (ana_form ps x) (st+1)) l)
                                      ((\x -> evalState (ana_form ps x) (st+1)) m)
      AS_BASIC.Negation l _      -> 
          if (isLiteral l)
          then
              do 
                return ps
          else
              do 
                st <- get 
                return $ sublogics_max need_PF $ (\x -> evalState (ana_form ps x) (st+1)) l
      AS_BASIC.Disjunction l _   -> 
                    let lprime = concat $ map Tools.flattenDis l in
                    if (foldl (&&) True $ map isLiteral lprime)
                    then
                        do 
                          if moreThanNLit lprime 1
                             then
                                 return $ sublogics_max need_CNF ps
                             else
                                 return ps
                    else
                        do 
                          st <- get 
                          return $ sublogics_max need_PF
                                     (comp_list $ map 
                                      (\x -> evalState (ana_form ps x) (st+1)) 
                                      lprime)     
      AS_BASIC.True_atom  _      -> do return ps
      AS_BASIC.False_atom _      -> do return ps
      AS_BASIC.Predication _     -> do return ps

moreThanNLit :: [AS_BASIC.FORMULA] -> Int -> Bool
moreThanNLit form n = (foldl (\y x -> if (x == True) then y + 1 else y) 0 $ map isPosLiteral form) > n

-- determines wheter a Formula is a literal
isLiteral :: AS_BASIC.FORMULA -> Bool
isLiteral (AS_BASIC.Predication _)       = True
isLiteral (AS_BASIC.Negation (AS_BASIC.Predication _) _ ) = True
isLiteral (AS_BASIC.Negation _ _) = False
isLiteral (AS_BASIC.Conjunction _ _) = False
isLiteral (AS_BASIC.Implication _ _ _) = False
isLiteral (AS_BASIC.Equivalence _ _ _) = False
isLiteral (AS_BASIC.Disjunction _ _) = False
isLiteral (AS_BASIC.True_atom  _ ) = True
isLiteral (AS_BASIC.False_atom _) = True

-- determines wheter a Formula is a positive literal
isPosLiteral :: AS_BASIC.FORMULA -> Bool
isPosLiteral (AS_BASIC.Predication _)       = True
isPosLiteral (AS_BASIC.Negation _ _) = False
isPosLiteral (AS_BASIC.Conjunction _ _) = False
isPosLiteral (AS_BASIC.Implication _ _ _) = False
isPosLiteral (AS_BASIC.Equivalence _ _ _) = False
isPosLiteral (AS_BASIC.Disjunction _ _) = False
isPosLiteral (AS_BASIC.True_atom  _ ) = True
isPosLiteral (AS_BASIC.False_atom _) = True

-- | determines subloig for basic items
sl_basic_items :: PropSL -> AS_BASIC.BASIC_ITEMS -> PropSL
sl_basic_items ps bi =
    case bi of 
      AS_BASIC.Pred_decl _    -> ps
      AS_BASIC.Axiom_items xs -> comp_list $ map (sl_form ps) $ 
                                 map AS_Anno.item xs

-- | determines sublogic for basic spec
sl_basic_spec :: PropSL -> AS_BASIC.BASIC_SPEC -> PropSL
sl_basic_spec ps (AS_BASIC.Basic_spec spec) = 
    comp_list $ map (sl_basic_items ps) $ 
              map AS_Anno.item spec

-- | all sublogics
sublogics_all :: [PropSL]
sublogics_all = 
    [PropSL
     {
       format    = CNF
     , has_imp   = False
     , has_equiv = False 
     }
    , PropSL
     {
       format    = HornClause
     , has_imp   = False
     , has_equiv = False 
     }
    ,PropSL
     {
       format    = PlainFormula
     , has_imp   = False
     , has_equiv = False 
     }
    ,PropSL
     {
       format    = PlainFormula
     , has_imp   = True
     , has_equiv = False 
     }
    ,PropSL
     {
       format    = PlainFormula
     , has_imp   = False
     , has_equiv = True
     }
    ,PropSL
     {
       format    = PlainFormula
     , has_imp   = True
     , has_equiv = True 
     }
    ]

-------------------------------------------------------------------------------
-- Conversion functions to String                                            --
-------------------------------------------------------------------------------

sublogics_name :: PropSL -> [String]
sublogics_name f =
    case formType of
      CNF -> ["CNF"]
      HornClause -> ["HornClause"]
      PlainFormula -> ["Prop" ++ 
                      (
                       if (imp) then "I" else ""
                      ) ++
                     (
                      if (equ) then "E" else ""
                     )]
    where formType = format f
          imp      = has_imp f
          equ      = has_equiv f

-------------------------------------------------------------------------------
-- Projections to sublogics                                                  --
-------------------------------------------------------------------------------

prSymbolM :: PropSL -> Symbol.Symbol -> Maybe Symbol.Symbol
prSymbolM _ sym = Just sym

prSig :: PropSL -> Sign.Sign -> Sign.Sign
prSig _ sig = sig

prMor :: PropSL -> Morphism.Morphism -> Morphism.Morphism
prMor _ mor = mor

prSymMapM :: PropSL 
          -> AS_BASIC.SYMB_MAP_ITEMS 
          -> Maybe AS_BASIC.SYMB_MAP_ITEMS
prSymMapM _ sMap = Just sMap

prSymM :: PropSL -> AS_BASIC.SYMB_ITEMS -> Maybe AS_BASIC.SYMB_ITEMS
prSymM _ sym = Just sym

-- keep an element if its computed sublogic is in the given sublogic
--

prFormulaM :: PropSL -> AS_BASIC.FORMULA -> Maybe AS_BASIC.FORMULA
prFormulaM sl form 
           | compareLE (sl_form bottom form) sl = Just form
           | otherwise                          = Nothing

prPredItem :: PropSL -> AS_BASIC.PRED_ITEM -> AS_BASIC.PRED_ITEM
prPredItem _ prI = prI

prBASIC_items :: PropSL -> AS_BASIC.BASIC_ITEMS -> AS_BASIC.BASIC_ITEMS
prBASIC_items pSL bI =
    case bI of
      AS_BASIC.Pred_decl pI -> AS_BASIC.Pred_decl $ prPredItem pSL pI
      AS_BASIC.Axiom_items aIS -> AS_BASIC.Axiom_items $ concat $ map mapH aIS 
    where 
      mapH :: AS_Anno.Annoted (AS_BASIC.FORMULA) 
           -> [(AS_Anno.Annoted (AS_BASIC.FORMULA))]
      mapH annoForm = let formP = prFormulaM pSL $ AS_Anno.item annoForm in
                      case formP of
                        Nothing -> []
                        Just f  -> [ AS_Anno.Annoted
                                   {
                                     AS_Anno.item = f
                                   , AS_Anno.opt_pos = AS_Anno.opt_pos annoForm
                                   , AS_Anno.l_annos = AS_Anno.l_annos annoForm
                                   , AS_Anno.r_annos = AS_Anno.r_annos annoForm
                                   }
                                   ]

prBasicSpec :: PropSL -> AS_BASIC.BASIC_SPEC -> AS_BASIC.BASIC_SPEC
prBasicSpec pSL (AS_BASIC.Basic_spec bS) =  
    AS_BASIC.Basic_spec $ map mapH bS
    where
      mapH :: AS_Anno.Annoted (AS_BASIC.BASIC_ITEMS)
           -> AS_Anno.Annoted (AS_BASIC.BASIC_ITEMS)
      mapH aBI = AS_Anno.Annoted
                 {
                   AS_Anno.item = prBASIC_items pSL $ AS_Anno.item aBI
                 , AS_Anno.opt_pos = AS_Anno.opt_pos aBI
                 , AS_Anno.l_annos = AS_Anno.l_annos aBI
                 , AS_Anno.r_annos = AS_Anno.r_annos aBI
                 }

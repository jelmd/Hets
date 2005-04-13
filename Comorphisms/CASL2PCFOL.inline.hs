{- 
Module      :  $Header$
Copyright   :  (c) Zicheng Wang, Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  portable

   Coding out subsorting (SubPCFOL= -> PCFOL=), 
   following Chap. III:3.1 of the CASL Reference Manual
-}

module Comorphisms.CASL2PCFOL where

import Logic.Logic
import Logic.Comorphism
import Common.Id
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import qualified Common.Lib.Rel as Rel
import Common.AS_Annotation
import Common.ListUtils
import Data.List

-- CASL
import CASL.Logic_CASL 
import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Morphism 
import CASL.Sublogic
import CASL.Inject
import CASL.Project
import CASL.Overload
import CASL.StaticAna

-- | The identity of the comorphism
data CASL2PCFOL = CASL2PCFOL deriving (Show)

instance Language CASL2PCFOL -- default definition is okay

instance Comorphism CASL2PCFOL
               CASL CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               Symbol RawSymbol ()
               CASL CASL_Sublogics
               CASLBasicSpec CASLFORMULA SYMB_ITEMS SYMB_MAP_ITEMS
               CASLSign 
               CASLMor
               Symbol RawSymbol () where
    sourceLogic CASL2PCFOL = CASL
    sourceSublogic CASL2PCFOL = CASL_SL
                      { has_sub = True,
                        has_part = True,
                        has_cons = True,
                        has_eq = True,
                        has_pred = True,
                        which_logic = FOL
                      }
    targetLogic CASL2PCFOL = CASL
    targetSublogic CASL2PCFOL = CASL_SL
                      { has_sub = False, -- subsorting is coded out
                        has_part = True,
                        has_cons = True,
                        has_eq = True,
                        has_pred = True,
                        which_logic = FOL
                      }
    map_theory CASL2PCFOL = mkTheoryMapping ( \ sig -> 
      let e = encodeSig sig in return (e, generateAxioms sig))
      (map_sentence CASL2PCFOL)
    map_morphism CASL2PCFOL mor = return 
      (mor  { msource =  encodeSig $ msource mor,
              mtarget =  encodeSig $ mtarget mor })
      -- other components need not to be adapted!
    map_sentence CASL2PCFOL _ = return . f2Formula
    map_symbol CASL2PCFOL = Set.single . id

-- | Add injection, projection and membership symbols to a signature
encodeSig :: Sign f e -> Sign f e
encodeSig sig
  = if Rel.isEmpty rel then sig else
      sig{sortRel = Rel.empty, opMap = projOpMap}
  where 
        rel = Rel.irreflex $ sortRel sig
        total (s, s') = OpType{opKind = Total, opArgs = [s], opRes = s'}
        partial (s, s') = OpType{opKind = if Rel.member s' s rel 
                                 then Total 
                                 else Partial, opArgs = [s'], opRes = s}
        setinjOptype = Set.image total $ Rel.toSet rel
        setprojOptype = Set.image partial $ Rel.toSet rel
        injOpMap = Map.insert injName setinjOptype $ opMap sig
        projOpMap = Map.insert projName setprojOptype $ injOpMap
    -- membership predicates are coded out

generateAxioms :: Eq f => Sign f e -> [Named (FORMULA f)]
generateAxioms sig = monotonicities sig ++ 
  concat([inlineAxioms CASL
     "  sorts s < s' \
      \ op inj : s->s' \
      \ forall x,y:s . inj(x)=e=inj(y) => x=e=y  %(ga_embedding_injectivity)% "
    ++ inlineAxioms CASL
      " sort s<s' \
      \ op pr : s'->?s \
      \ forall x,y:s'. pr(x)=e=pr(y)=>x=e=y   %(ga_projection_injectivity)% " 
    ++ inlineAxioms CASL
     " sort s< s' \
      \ op pr : s'->?s ; inj:s->s' \
      \ forall x:s . pr(inj(x))=e=x             %(ga_projection)% " 
      | s <- sorts, 
        s' <- minSupers s]
   ++ [inlineAxioms CASL
     " sort s<s';s'<s'' \
      \ op inj:s'->s'' ; inj: s->s' ; inj:s->s'' \
      \ forall x:s . inj(inj(x))=e=inj(x)      %(ga_transitivity)% "  
          | s <- sorts, 
            s' <- minSupers s,
            s'' <- minSupers s',
            s'' /= s]
   ++ [inlineAxioms CASL
     " sort s<s';s'<s \
      \ op inj:s->s' ; inj: s'->s \
      \ forall x:s . inj(inj(x))=e=x      %(ga_identity)% "  
          | s <- sorts, 
            s' <- minSupers s,
            Set.member s $ supersortsOf s' sig2])
    where 
        x = mkSimpleId "x"
        y = mkSimpleId "y"
        inj = injName
        pr = projName
        minSupers so = keepMinimals sig2 id $ Set.toList $ Set.delete so 
                           $ supersortsOf so sig2
        sorts = Set.toList $ sortSet sig
        sig2 = sig { sortRel = Rel.irreflex $ sortRel sig }

monotonicities :: Sign f e -> [Named (FORMULA f)]
monotonicities sig = 
    concatMap (makeMonos sig) (Map.toList $ opMap sig)
    ++ concatMap (makePredMonos sig) (Map.toList $ predMap sig)

makeMonos :: Sign f e -> (Id, Set.Set OpType) -> [Named (FORMULA f)]
makeMonos sig (o, ts) = 
   concatMap (makeEquivMonos o sig) $ equivalence_Classes (leqF sig) 
             $ Set.toList ts

makePredMonos :: Sign f e -> (Id, Set.Set PredType) -> [Named (FORMULA f)]
makePredMonos sig (p, ts) = 
   concatMap (makeEquivPredMonos p sig) $ equivalence_Classes (leqP sig) 
             $ Set.toList ts

makeEquivMonos :: Id -> Sign f e -> [OpType] -> [Named (FORMULA f)]
makeEquivMonos o sig ts = 
  case ts of
  [] -> []
  t : rs -> concatMap (makeEquivMono o sig t) rs ++
            makeEquivMonos o sig rs

makeEquivPredMonos :: Id -> Sign f e -> [PredType] -> [Named (FORMULA f)]
makeEquivPredMonos o sig ts = 
  case ts of
  [] -> []
  t : rs -> concatMap (makeEquivPredMono o sig t) rs ++
            makeEquivPredMonos o sig rs

makeEquivMono :: Id -> Sign f e -> OpType -> OpType -> [Named (FORMULA f)]
makeEquivMono o sig o1 o2 =     
      let rs = minimalSupers sig (opRes o1) (opRes o2)
          args = permute $ zipWith (maximalSubs sig) (opArgs o1) (opArgs o2)
      in concatMap (makeEquivMonoRs o o1 o2 rs) args 

makeEquivMonoRs :: Id -> OpType -> OpType -> 
                   [SORT] -> [SORT] -> [Named (FORMULA f)]
makeEquivMonoRs o o1 o2 rs args = map (makeEquivMonoR o o1 o2 args) rs

makeEquivMonoR :: Id -> OpType -> OpType -> 
                  [SORT] -> SORT -> Named (FORMULA f)
makeEquivMonoR o o1 o2 args res = 
    let vds = zipWith (\ s n -> Var_decl [mkSelVar "x" n] s []) args [1..]
        a1 = zipWith (\ v s -> 
                      inject [] (toQualVar v) s) vds $ opArgs o1
        a2 = zipWith (\ v s -> 
                      inject [] (toQualVar v) s) vds $ opArgs o2
        t1 = inject [] (Application (Qual_op_name o (toOP_TYPE o1) []) a1 [])
             res
        t2 = inject [] (Application (Qual_op_name o (toOP_TYPE o2) []) a2 []) 
             res
    in  NamedSen { senName = "ga_function_monotonicity",
                   sentence = mkForall vds
                      (Existl_equation t1 t2 []) [] }

makeEquivPredMono :: Id -> Sign f e -> PredType -> PredType 
                  -> [Named (FORMULA f)]
makeEquivPredMono o sig o1 o2 =     
      let args = permute $ zipWith (maximalSubs sig) (predArgs o1) 
                 $ predArgs o2
      in map (makeEquivPred o o1 o2) args 

makeEquivPred :: Id -> PredType -> PredType -> [SORT] -> Named (FORMULA f)
makeEquivPred o o1 o2 args = 
    let vds = zipWith (\ s n -> Var_decl [mkSelVar "x" n] s []) args [1..]
        a1 = zipWith (\ v s -> 
                      inject [] (toQualVar v) s) vds $ predArgs o1
        a2 = zipWith (\ v s -> 
                      inject [] (toQualVar v) s) vds $ predArgs o2
        t1 = Predication (Qual_pred_name o (toPRED_TYPE o1) []) a1 []
        t2 = Predication (Qual_pred_name o (toPRED_TYPE o2) []) a2 []
    in  NamedSen { senName = "ga_predicate_monotonicity",
                   sentence = mkForall vds
                      (Equivalence t1 t2 []) [] }

-- | all maximal common subsorts of the two input sorts
maximalSubs :: Sign f e -> SORT -> SORT -> [SORT]
maximalSubs s s1 s2 = 
    keepMaximals s id $ Set.toList $ common_subsorts s s1 s2

keepMaximals :: Sign f e -> (a -> SORT) -> [a] -> [a]
keepMaximals s' f' l = keepMaximals2 s' f' l l
    where keepMaximals2 s f l1 l2 = case l1 of
              [] -> l2
              x : r -> keepMaximals2 s f r $ filter 
                   ( \ y -> let v = f x 
                                w = f y 
                            in leq_SORT s v w ||
                            not (geq_SORT s v w)) l2
 
f2Formula :: FORMULA f -> FORMULA f
f2Formula = projFormula id . injFormula id 

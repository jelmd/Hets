{- |
Module      :  $Header$
Copyright   :  (c) Paolo Torrini and Till Mossakowski and Uni Bremen 2003
Licence     :  All rights reserved.

Maintainer  :  hets@tzi.de
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

   The embedding comorphism from Haskell to Isabelle-HOLCF.

relevant files:

Stratego.BaseStruct2Stratego2
Stratego.Prop2Stratego2

TI.OrigTIMonad

This one translates directly from OrigTiMonad. Problems with constants that are not exported by Programatica.
-}

module Comorphisms.Haskell2IsabelleHOLCF where

import Logic.Logic
import Logic.Comorphism
import Common.Result as Result
import Common.Id as Id
import qualified Common.Lib.Map as Map
import Data.List
import Data.Maybe
import Common.AS_Annotation (Named)

-- Haskell
import Haskell.Logic_Haskell as LH
import Haskell.HatParser as HatParser hiding (HsType)
import Haskell.HatAna as HatAna

-- Isabelle
import Isabelle.IsaSign as IsaSign
import Isabelle.Logic_Isabelle
import Isabelle.IsaConsts as IsaConsts
-- import Isabelle.IsaPrint

-- New imports
import Isabelle.Translate as Translate
-- import Translate 

import FiniteMap
import HsTypeStruct  
import HsKindStruct
import HsTypeMaps 
import HsName 
import HsIdent 
import TypedIds
import OrigTiMonad 
import TiTypes
import TiKinds
import TiInstanceDB -- as TiInst
import TiTEnv
import TiKEnv
import TiEnvFM
import PNT 
import UniqueNames
-- import Programatica.property.PropSyntaxRec as PropSyn
import PropSyntaxRec 
import HsExpStruct
import HsPatStruct
import HsExpMaps
import HsPatMaps

import SyntaxRec

import TiPropDecorate
import PropSyntaxStruct
import HsDeclStruct
import HsGuardsStruct
import TiDecorate

-- The identity of the comorphism
data Haskell2IsabelleHOLCF = Haskell2IsabelleHOLCF deriving (Show)

instance Language Haskell2IsabelleHOLCF -- default definition is okay

------------------------------- Type synonims --------------------------------------

-- type PNT = PNT.PNT

type HsInstance = TiInstanceDB.Instance PNT
type HsInstances = [TiInstanceDB.Instance PNT]
type HsIClause = TiTypes.Pred PNT
type HsType = TiTypes.Type PNT
type HsClass = TiTypes.Type PNT

-- type IsaClass = IsaSign.IsaClass
type IsaSort = IsaSign.Sort
type IsaType = IsaSign.Typ
type IsaTerm = IsaSign.Term
type IsaPattern = IsaSign.Term

type IsaTypeInsts = (TName, [(IsaClass, [(IsaType, [IsaClass])])])

type VaMap = Map.Map (HsIdentI PNT) (Scheme PNT) 
type TyMap = Map.Map (HsIdentI PNT) (Kind, TiTypes.TypeInfo PNT)
-- type FiMap = Map.Map (HsIdentI (SN Id)) HsFixity

type Dec = TiPropDecorate.TiDecl

------------------------------ Comorphism -----------------------------------------

instance Comorphism Haskell2IsabelleHOLCF -- multi-parameter class Com.
               Haskell ()
               HatParser.HsDecls (HatAna.TiDecl PNT) () ()
               HatAna.Sign HaskellMorphism
               () () ()
               Isabelle () () IsaSign.Sentence () ()
               IsaSign.Sign 
               () () () ()  where
    sourceLogic _ = Haskell
    sourceSublogic _ = ()
    targetLogic _ = Isabelle
    targetSublogic _ = ()
    map_sign _ = transSignature
    map_sentence _ = transSentence
--    map_theory _ = transTheory

------------------------------ Isa auxiliaries ----------------------------------

-- multiCApp :: Term [IsaTerm] -> IsaTerm 
-- multiCApp t ls = case ls of 
--                 [] -> t
--                 x:xs -> multiCApp (App t x IsCont) xs 

------------------------------ Theory translation -------------------------------

transSentence :: HatAna.Sign -> TiPropDecorate.TiDecl PNT -> Result IsaSign.Sentence
transSentence sign (TiPropDecorate.Dec d) = case d of
             PropSyntaxStruct.Base p -> case p of
                HsDeclStruct.HsFunBind _ ls -> Result [] (Just (Sentence $ transMatchList ls)) 
--                HsDeclStruct.HsTypeSig _ ls c t -> Result [] (Just (Sentence (functionDeclList ls c t)))
--                _ -> Result [(Diag Hint "problem" (Id.SourcePos "Haskell2IsabelleHOLCF.transSentence" 137 1))] (Nothing)
                _ -> error "Haskell2IsabelleHOLCF.transSentence 2, not yet supported"
--             _ -> Result [(Diag Hint "problem" (Id.SourcePos "Haskell2IsabelleHOLCF.transSentence" 136 1))] (Nothing)
             _ -> error "Haskell2IsabelleHOLCF.transSentence 1, case not yet supported"

-- fuctionDecl :: PNT -> [HsTypeI PNT] -> HsTypeI PNT -> IsaTerm
-- functionDecl n c t = 

transMatch :: 
  HsDeclStruct.HsMatchI PNT (TiPropDecorate.TiExp PNT) p ds -> IsaTerm 
transMatch t = case t of 
  (HsDeclStruct.HsMatch _ nm _ (HsGuardsStruct.HsBody x) _) -> 
          App (App (Const "IsaEq" noType) (Const (showIsaS nm) noType) IsCont) (transExp x) IsCont
  _ -> error "Haskell2IsabelleHOLCF.transMatch, case not yet supported"

transMatchList ::  [HsDeclStruct.HsMatchI PNT (TiPropDecorate.TiExp PNT) p ds] -> IsaTerm
transMatchList ls = case ls of
   [] -> Bottom
   x:xs -> Fix (IsaConsts.mkIsaOr (transMatch x) (transMatchList xs)) 

-- transTheory :: (HatAna.Sign, [TiPropDecorate.TiDecls PNT] -> 
--                      Result (IsaSign.Sign, [Named IsaSign.Sentence])  
--transTheory (sign, decls) = do x <- transSignature sign
--                               y <- maybeResult x
--                            return [] (y, transDeclsL decls)
{-
transDeclsL ::  [TiPropDecorate.TiDecls PNT] -> [Named IsaSign.Sentence]
transDeclsL ds = concat (map transDecl ds)

transDecls ::  TiPropDecorate.TiDecls PNT -> [Named IsaSign.Sentence]
transDecls ds = case Decs x _ -> transDecl x

transDecl ::  TiPropDecorate.TiDecl PNT -> Named IsaSign.Sentence
transDecl (Dec d) = case d of
             Base p -> case p of
                HsFunBind _ ls -> NamedSen [] (map transMatch ls) 

transMatch :: 
  HsMatch PNT (HsRhs (PropSyntaxRec.HsExpI PNT)) p ds ->IsaSign.Definition 
transMatch (HsMatch _ nm _ x _) -> transDef nm x
--           Prop p ->

transDef :: PNT -> HsRhs (PropSyntaxRec.HsExpI PNT) -> IsaSign.Definition
transDef l r = case r of HsBody e -> (showIsaS l, transExp r)
-}

------------------------------ Signature translation -----------------------------

transSignature :: HatAna.Sign -> Result (IsaSign.Sign, [Named IsaSign.Sentence]) 

transSignature sign = Result [] 
 (Just (IsaSign.Sign{
    baseSig = "MainHC",
    tsig = emptyTypeSig 
           { 
             classrel = Map.union Map.empty $ getClassrel (HatAna.types sign),
             abbrs = Map.union Map.empty $ getAbbrs (HatAna.types sign),
             arities = Map.union Map.empty $ getArities (HatAna.instances sign) 
           },
    constTab = Map.union Map.empty $ getConstTab (HatAna.values sign),
--    constTab = Map.foldWithKey insertOps 
--                               Map.empty 
--                               (assumps sign),
    domainTab = getDomainTab (HatAna.types sign) (HatAna.values sign),
    showLemmas = False },
    [] ))  -- for now, no sentences


------------------------------- Signature --------------------------------------
-------------------------------- Name translation -----------------------------

-- Translating to strings compatible with Isabelle-HOLCF

showIsaS :: Show i => i -> IsaSign.IName
showIsaS x = (Translate.transString) (show x)

--showIsaPNT :: PNT -> IsaSign.IName
--showIsaPNT t = 

-------------------------------- Identifier translation -----------------------

idTrans :: Show i => HsIdent.HsIdentI i -> IsaSign.Term
idTrans t = case t of
                 HsVar x -> Free (showIsaS x) noType
                 HsCon x -> Const (showIsaS x) noType

------------------------------- Kind translation ------------------------------

simpleKind :: TiKinds.Kind -> Bool
simpleKind x = case x of 
                 K HsKindStruct.Kstar -> True
                 K (HsKindStruct.Kfun a b) -> (simpleKind a) && (simpleKind b)
                 _ -> False 

kindTrans :: TiKinds.Kind -> IsaSign.IsaKind
kindTrans x = case x of 
                 K HsKindStruct.Kstar -> IsaSign.Star
                 K (HsKindStruct.Kfun a b) -> IsaSign.Kfun (kindTrans a) (kindTrans b)
                 _ -> error "Hs2HOLCF.kindTrans,"

kindExTrans :: TiKinds.Kind -> IsaSign.ExKind
kindExTrans x = case x of 
                 K HsKindStruct.Kstar -> IKind IsaSign.Star
                 K (HsKindStruct.Kfun a b) -> IKind (IsaSign.Kfun (kindTrans a) (kindTrans b))
                 K HsKindStruct.Kpred -> IClass
                 K HsKindStruct.Kprop -> PLogic
                 _ -> error "Hs2HOLCF.kindExTrans, kind variables not supported"


------------------------------ Type translation -------------------------------
{- This signature translation takes after the one to Stratego, and relies on 
 Isabelle.Translation to solve naming conflicts. -}

transT :: Show d => (PNT -> IsaType) -> (PNT -> IsaType) -> (d -> IsaType) -> 
                  HsTypeStruct.TI PNT d -> IsaType
transT trIdV trIdC trT t =
  case HsTypeMaps.mapTI2 trIdV trIdC trT t of
    HsTyFun t1 t2 -> IsaSign.mkContFun t1 t2
    HsTyApp t1 t2 -> IsaSign.typeAppl t1 [t2]
    HsTyVar a -> a
    HsTyCon c -> c 
    _ -> not_supported "Type" t

-- error :: forall a. [Char] -> a
not_supported :: (Show t, Show i) => String -> HsTypeStruct.TI i t -> a
not_supported s x = error $ s++" not supported (yet): "++show x

transIdV :: PNT -> IsaType
transIdV t = TFree (showIsaS t) IsaSign.dom

transIdC :: PNT -> IsaType
transIdC t = 
  case (UniqueNames.orig t) of 
    UniqueNames.G m n _ -> 
         IsaSign.Type ((showIsaS m)++"."++(showIsaS n)) IsaSign.dom (transFields t) 
    _ -> IsaSign.Type (showIsaS t) IsaSign.dom (transFields t)

transFields ::  PNT -> [IsaType]
transFields t = case t of 
    PNT _ (TypedIds.Type q) _ -> [TFree (showIsaS x) IsaSign.dom | x <- TypedIds.fields q]
    _ -> error "Haskell2IsabelleHOLCF.transFields"

transType :: HsType -> IsaType
transType (Typ t) = transT transIdV transIdC transType t

------------------------------ Class translation ------------------------------

mkIsaClass :: CName -> IsaClass
mkIsaClass n = IsaClass n

transClass :: HsType -> IsaClass
transClass x = case x of 
                     Typ (HsTyCon c) -> IsaClass (showIsaS c)
                     Typ _           -> error "Hs2HOLCF.transClass"
-- maybe need check for parameters?

----------------------------- auxiliary lift function ------------------------

liftMapByList :: (x -> [(a,b)]) -> ([(c,d)] -> y) -> (a -> c) -> (b -> d) -> x -> y
liftMapByList ma mb h k f = mb [(h a, k b) | (a, b) <- ma f] 

liftMapByListF :: (x -> [(a,b)]) -> ([(c,d)] -> y) -> (a -> c) -> (b -> d) -> (a -> Bool) -> x -> y
liftMapByListF ma mb h k cs f = mb [(h a, k b) | (a, b) <- ma f, cs a] 

------------------------------- getting ConstTab ------------------------------

getConstTab ::  VaMap -> IsaSign.ConstTab
getConstTab f =   
    liftMapByList Map.toList Map.fromList showIsaS transFromScheme f

transFromScheme :: TiTypes.Scheme PNT -> IsaType
transFromScheme s = case s of 
    Forall _ _ (_ TiTypes.:=> t) -> transType t
    _ -> error "Haskell2IsabelleHOLCF.transFromScheme"

----------------------------- getting Classrel (from KEnv) -----------------------

getClassrel ::  TyMap -> IsaSign.Classrel
getClassrel f = 
     liftMapByList Map.toList Map.fromList (mkIsaClass . showIsaS) transClassInfo f

transClassInfo :: (Kind, TiTypes.TypeInfo PNT) -> [IsaClass]
transClassInfo p = map transClass (extClassInfo $ snd p)

extClassInfo :: TiTypes.TypeInfo PNT -> [HsClass]
extClassInfo p = case p of 
        TiTypes.Class a _ _ _ -> map getInstType a -- ?? error ???
        _ -> error "Haskell2IsabelleHOLCF.extClassInfo"     
 
---------------------------- getting Abbrs (from KEnv) -----------------------------
 
getAbbrs ::  TyMap -> IsaSign.Abbrs
getAbbrs f = 
    liftMapByList Map.toList Map.fromList showIsaS transAbbrsInfo f

transAbbrsInfo :: (Kind, TiTypes.TypeInfo PNT) -> ([IsaSign.TName], IsaType)
transAbbrsInfo p = let x = extAbbrsInfo (snd p) in (map showIsaS (fst x), transType (snd x))

extAbbrsInfo :: TiTypes.TypeInfo PNT -> ([PNT], HsType)
extAbbrsInfo p = case p of 
           TiTypes.Synonym ls t -> (ls, t)
           _ -> error "extAbbrsInfo"
 
------------------------------ getting Arities ------------------------------------

getArities :: HsInstances -> IsaSign.Arities
getArities db = Map.fromList $ getIsaInsts db  

getIsaInsts :: HsInstances -> [IsaTypeInsts]
getIsaInsts db = map transTypeInsts (getTypeInsts db)

getTypeInsts :: HsInstances -> [(HsType, HsInstances)]
getTypeInsts db = 
  [(t, [x | x <- db, getMainInstType x == t]) 
                    | t <- remove_duplicates (map getMainInstType db)]

transTypeInsts :: (HsType, HsInstances) -> IsaTypeInsts
transTypeInsts (a,b) = (showIsaS a, map transInst b)

{-
getArities :: TiInstanceDB.IDB PNT -> IsaSign.Arities
getArities db = case db of
   (Idb f) -> 
     liftMapByList FiniteMap.fmToList Map.fromList showIsaS (map transInst) f
-}    
------------------------------ auxiliaries ----------------------------------------

remove_duplicates :: (Eq a) => [a] -> [a]
remove_duplicates ls = remove_dupes ls []

remove_dupes :: (Eq a) => [a] -> [a] -> [a]
remove_dupes ls ms = case ls of x:rs -> if (elem x (rs ++ ms)) then remove_dupes rs ms
                                                                   else remove_dupes rs (x:ms)
                                [] -> ms

getMainInstType :: HsInstance -> HsType
getMainInstType i = case i of (Typ (HsTyApp _ t), _) -> t

getMainInstClass :: HsInstance -> HsClass
getMainInstClass i = case i of (Typ (HsTyApp c _), _) -> c

getInstType :: HsIClause -> HsType
getInstType i = case i of (Typ (HsTyApp _ t)) -> t
 
getInstClass :: HsIClause -> HsType
getInstClass i = case i of (Typ (HsTyApp c _)) -> c

getInstPrems :: HsInstance -> [HsIClause]
getInstPrems i = case i of (_, (_, ls)) -> ls

-------------- corresponding change in IsaSign

transInst :: HsInstance -> (IsaClass, [(IsaType, [IsaClass])])
transInst i = let x = prepInst i in 
         (transClass $ fst x, [(transType a, map transClass b) | (a,b) <- snd x])

prepInst :: HsInstance -> (HsClass, [(HsType, [HsClass])])
prepInst i = (getMainInstClass i, prepInst1 i)

prepInst1 :: HsInstance -> [(HsType, [HsClass])]
prepInst1 i = [(x, [getInstClass y | y <- getInstPrems i, getInstType y == x]) 
              | x <- map getInstType (getInstPrems i)] 

-- prepInst1 :: HsInstance -> [(HsType, [HsClass])]
-- prepInst1 i = [(transType x, [transClass $ getInstClass y | y <- getInstPrems i, getInstType y == x]) 
--              | x <- map getInstType (getInstPrems i)] 

{------ old version 

transInst :: HsInstance -> (IsaClass, [[IsaClass]])
transInst i = let x = prepInst i in 
         (transClass $ fst x, map (map transClass) (snd x))

prepInst :: HsInstance -> (HsClass, [[HsClass]])
prepInst i = 
  (getMainInstClass i, map snd (prepInst1 i))

prepInst1 :: HsInstance -> [(HsType, [HsClass])]
prepInst1 i = prepInst2 (getTypeVars $ getMainInstType i) (getInstPrems i)

prepInst2 :: [HsType] -> [HsIClause] -> [(HsType, [HsClass])]
prepInst2 vs cs = (prepInstR (reverse vs) cs []) 

prepInstR :: [HsType] -> [HsIClause] -> [(HsType, [HsClass])]
prepInstR vs ca cb = case vs of 
 [] -> cb
 x:xs -> prepInstR xs 
                   [y | <- ca, getInstType y \= x]  
                   (x, [getInstClass y | y <- ca, getInstType y = x]):cb

getTypeVars :: HsType -> [HsType]
getTypeVars t = remove_duplicates (getTypeVarsR [t] [])

getTypeVarsR :: [HsType] -> [HsType] -> [HsType]
getTypeVarsR as ls = case as of 
      [] -> ls
      x:xs ->  case x of 
               (_ t1 t2) -> getTypeVarsR t1:t2:xs ls
               HsTyVar v -> getTypeVarsR xs (append ls [v])
               HsTyCon c -> getTypevarsR xs ls

-}

------------------------------- getting Type Constructors ---------------------

getTyCons :: TyMap -> VaMap -> Map.Map IsaSign.TName IsaType
getTyCons g f =  
     liftMapByListF Map.toList Map.fromList showIsaS transFromScheme (checkTyCons g) f 

checkTyCons :: TyMap -> HsIdent.HsIdentI PNT -> Bool
checkTyCons f n = case Map.lookup n f of 
                      Just (_, d) -> if d == TiTypes.Data || d == TiTypes.Newtype then True else False
                      _ -> error "Haskell2IsabelleHOLCF.checkTyCons"

---------------------------- checking mutual dependencies -----------------------

-- type DomainTab = [DomainTabEntry]
-- type DomainTabEntry = [DomainEntry] -- (type,[value cons])
-- type DomainEntry = (Typ,[DomainAlt])
-- type DomainAlt = (VName,[Typ])

getDepDoms :: [[IsaSign.DomainEntry]] -> IsaSign.DomainTab
getDepDoms ls = checkDep (abCheckDep mutDep) (tail ls) [head ls] []

abCheckDep :: (a -> a -> Bool) -> [a] -> [a] -> Bool
abCheckDep f as bs = genOr (\x -> genOr (f x) bs) as  

checkDep ::  ([x] -> [x] -> Bool) -> [[x]] -> [[x]] -> [[x]] -> [[x]]
checkDep f ls ms cs = case ls of 
                         a:as -> case ms of 
                                   b:bs -> if (f a b) then checkDep f ((a ++ b):as) bs cs else checkDep f (a:as) bs (b:cs)
                                   [] -> checkDep f as cs []
                         [] -> ms 

mutDep :: DomainEntry -> DomainEntry -> Bool
mutDep a b = depOn a b || depOn b a

depOn :: DomainEntry -> DomainEntry -> Bool
depOn x y = case (x,y) of 
              ((a,_),(_,bs)) -> genOr (subTypForm a) (concat (map snd bs))                       

genOr :: (a -> Bool) -> [a] -> Bool
genOr f ys = case ys of 
               [] -> False
               x:xs -> if (f x) then True 
                           else (genOr f xs)

subTypForm :: Typ -> Typ -> Bool
subTypForm t1 t2 = case t2 of 
      IsaSign.Type a b cs -> 
                  if a == IsaSign.typeId t1 &&
                     b == IsaSign.typeSort t1 then True 
                  else genOr (subTypForm t1) cs
      _ -> False   

singList :: [a] -> [[a]]
singList list = [[a] | a <- list]

------------------------------- getting DomainTab -----------------------------

-- assuming kind has already been checked...
-- 
getDomainTab :: TyMap -> VaMap -> IsaSign.DomainTab 
getDomainTab g f =  
    getDepDoms $ singList [getDomainEntry (getConstTab f) (getHsType f x) | x <- Map.keys f, checkTyCons g x]

getHsType :: VaMap -> HsIdent.HsIdentI PNT -> HsType
getHsType f n = case Map.lookup n f of 
                               Just (Forall _ _ (_ TiTypes.:=> t)) -> t
                               _ -> error "Haskell2IsabelleHOLCF.getHsType"

getDomainEntry :: IsaSign.ConstTab -> HsType -> IsaSign.DomainEntry
getDomainEntry ctab t = 
 case t of
  Typ (HsTyCon (PNT _ (TypedIds.Type d) _)) -> 
   (transType t, [(b, getFieldTypes ctab b) | b <- [showIsaS $ conName c | c <- constructors d]])
  _ -> error "Haskell2IsabelleHOLCF.getDomainEntry" 
--   (transType t, [(showIsaS $ conName c, getFieldTypes ctab (showIsaS $ conName c))  
--                    | c <- constructors d]) 

getFieldTypes :: IsaSign.ConstTab -> IsaSign.VName -> [IsaType]
getFieldTypes ctab c = let x = Map.lookup c ctab in
                           case x of
                                  Nothing -> error "Haskell2IsabelleHOLCF.getFieldTypes"
                                  Just y -> argTypes y

argTypes :: IsaType -> [IsaType]
argTypes a = case a of
    IsaSign.Type "dFun" _ [b,c] -> b:argTypes c
    _ -> [] 

----------------------------------- Expressions -------------------------------

-- id :: i -> i
-- id x = x

mapEI5 :: (i1 -> i2) -> 
          (e1 -> e2) ->
          (p1 -> p2) ->
          EI i1 e1 p1 d t c ->
          EI i2 e2 p2 d t c
mapEI5 a b c e = HsExpMaps.mapEI a b c id id id e

transE :: (PNT -> IsaSign.VName) -> (e -> IsaTerm) -> (p -> IsaPattern) -> 
            (HsExpStruct.EI PNT e p j h k) -> IsaTerm
transE trId trE trP e =
 case (mapEI5 trId trE trP e) of 
   HsId (HsVar x)              -> Free x noType
   HsId (HsCon c)              -> Const c noType
   HsApp x y                   -> App x y IsCont 
--   HsLambda ps e               -> IsaSign.Abs [(x, noType) | x <- ps] e IsCont
--   HsLet ds e                  -> Let ds e 
   HsIf x y z                  -> If x y z 
--   HsCase e ds                 -> Case e ds 
   HsTuple es                  -> Tuples es IsCont 
   HsParen e                   -> Paren e
   _ -> error "Haskell2IsabelleHOLCF.transE, not supported"

transP :: (PNT -> IsaSign.VName) -> (p -> IsaPattern) -> 
            (HsPatStruct.PI PNT p) -> IsaPattern
transP trId trP p =
 case HsPatMaps.mapPI trId trP p of
   HsPId (HsVar x) -> Free x noType
   HsPId (HsCon c) -> Const c noType
--   HsPLit _ lit -> litPat (transL lit) -- new
--   HsPApp c ps -> App x y IsCont
   HsPTuple ps -> Tuples ps IsCont 
--   HsPList ps -> plist ps
   HsPParen p -> Paren p
-- HsPRec
--   HsPAsPat x p -> AsPattern (x,p)
   HsPWildCard -> Wildcard
--   HsPIrrPat p -> twiddlePat p
--   _ -> not_supported "Pattern" p
   _ -> error "Haskell2IsabelleHOLCF.transP, not supported"

transPat :: TiDecorate.TiPat PNT -> IsaPattern
transPat x = case x of 
    (TiDecorate.Pat p) -> transP showIsaS transPat p
    _ -> error "Haskell2IsabelleHOLCF.transPat"

-- transPat :: SyntaxRec.HsPatI PNT -> IsaPattern
-- transPat (Pat p) = transP showIsaS transPat p

extVars :: IsaPattern -> VName
extVars p = case p of 
    Free x _ -> x 
    _ -> error "Haskell2IsabelleHOLCF.extVars"

transExp :: TiPropDecorate.TiExp PNT -> IsaTerm
transExp t = case t of 
    (TiPropDecorate.Exp e) -> transE showIsaS transExp transPat e
    _ -> error "Haskell2IsabelleHOLCF.transExp"

-- transExp :: PropSyntaxRec.HsExpI PNT -> IsaTerm
-- transExp t = case t of 
--    (PropSyntaxRec.Exp e) -> transE showIsaS transExp transPat e

--    transE showIsaS transExp transE transLocalDecs e
--  where
--  transLocalDecs (a,b) = (transE a, transE b)


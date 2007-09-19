{- |
Module      :  $Header$
Description :  resolve type constraints
Copyright   :  (c) Christian Maeder and Uni Bremen 2003-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  experimental
Portability :  portable

constraint resolution
-}

module HasCASL.Constrain
    ( Constraints
    , Constrain(..)
    , noC
    , substC
    , joinC
    , insertC
    , shapeRel
    , monoSubsts
    , fromTypeVars
    , fromTypeMap
    , simplify
    ) where

import HasCASL.Unify
import HasCASL.As
import HasCASL.FoldType
import HasCASL.AsUtils
import HasCASL.Le
import HasCASL.PrintLe ()
import HasCASL.TypeAna
import HasCASL.ClassAna
import HasCASL.VarDecl

import qualified Data.Set as Set
import qualified Data.Map as Map
import qualified Common.Lib.Rel as Rel
import Common.Lib.State
import Common.Id
import Common.Result
import Common.Doc
import Common.DocUtils

import Control.Exception (assert)

import Data.List
import Data.Maybe

instance Pretty Constrain where
    pretty c = case c of
       Kinding ty k -> pretty $ KindedType ty (Set.singleton k) nullRange
       Subtyping t1 t2 -> fsep [pretty t1, less <+> pretty t2]

instance PosItem Constrain where
  getRange c = case c of
    Kinding ty _ -> getRange ty
    Subtyping t1 t2 -> getRange t1 `appRange` getRange t2

type Constraints = Set.Set Constrain

noC :: Constraints
noC = Set.empty

joinC :: Constraints -> Constraints -> Constraints
joinC = Set.union

insertC :: Constrain -> Constraints -> Constraints
insertC c = case c of
            Subtyping t1 t2 -> if t1 == t2 then id else Set.insert c
            Kinding _ k -> if k == universe then id else Set.insert c

substC :: Subst -> Constraints -> Constraints
substC s = Set.fold (insertC . ( \ c -> case c of
    Kinding ty k -> Kinding (subst s ty) k
    Subtyping t1 t2 -> Subtyping (subst s t1) $ subst s t2)) noC

simplify :: Env -> Constraints -> ([Diagnosis], Constraints)
simplify te rs =
    if Set.null rs then ([], noC)
    else let (r, rt) = Set.deleteFindMin rs
             Result ds m = entail te r
             (es, cs) = simplify te rt
             in (ds ++ es, case m of
                                 Just _ -> cs
                                 Nothing -> insertC r cs)

entail :: Monad m => Env -> Constrain -> m ()
entail te p =
    do is <- byInst te p
       mapM_ (entail te) $ Set.toList is

byInst :: Monad m => Env -> Constrain -> m Constraints
byInst te c = let cm = classMap te in case c of
    Kinding ty k -> if k == universe then
                        assert (rawKindOfType ty == ClassKind ())
                    $ return noC else
      let Result _ds mk = inferKinds (Just True) ty te in
                   case mk of
                   Nothing -> fail $ "constrain '" ++
                                  showDoc c "' is unprovable"
                   Just ((_, ks), _) -> if newKind cm k ks then
                       fail $ "constrain '" ++
                           showDoc c "' is unprovable" ++
                              if Set.null ks then "" else
                                  "\n  known kinds are: " ++ showDoc ks ""
                       else return noC
    Subtyping t1 t2 -> if lesserType te t1 t2 then return noC
                       else fail ("unable to prove: " ++ showDoc t1 " < "
                                  ++ showDoc t2 "")

freshTypeVarT :: Type -> State Int Type
freshTypeVarT t =
    do (var, c) <- freshVar $ Id [] [] $ getRange t
       return $ TypeName var (rawKindOfType t) c

toPairState :: State Int a -> State (Int, b) a
toPairState p =
    do (a, b) <- get
       let (r, c) = runState p a
       put (c, b)
       return r

addSubst :: Subst -> State (Int, Subst) ()
addSubst s = do
    (c, o) <- get
    put (c, compSubst o s)

swap :: (a, b) -> (b, a)
swap (a, b) = (b, a)

substPairList :: Subst -> [(Type, Type)] -> [(Type, Type)]
substPairList s = map ( \ (a, b) -> (subst s a, subst s b))

absOrExpandedAbs :: Type -> Bool
absOrExpandedAbs t = case t of
    TypeAbs _ _ _ -> True
    ExpandedType _ (TypeAbs _ _ _) -> True
    _ -> False

-- pre: shapeMatch succeeds
shapeMgu :: Env -> [(Type, Type)] -> State (Int, Subst) [(Type, Type)]
shapeMgu te cs =
    let (atoms, structs) = partition ( \ p -> case p of
                                       (TypeName _ _ _, TypeName _ _ _) -> True
                                       _ -> False) cs
    in case structs of
  [] -> return atoms
  p@(t1, t2) : tl -> let rest = tl ++ atoms in case p of
    (ExpandedType _ t, _) | noAbs t -> shapeMgu te $ (t, t2) : rest
    (_, ExpandedType _ t) | noAbs t -> shapeMgu te $ (t1, t) : rest
    (TypeAppl (TypeName l _ _) t, _) | l == lazyTypeId ->
        shapeMgu te $ (t, t2) : rest
    (_, TypeAppl (TypeName l _ _) t) | l == lazyTypeId ->
        shapeMgu te $ (t1, t) : rest
    (KindedType t _ _, _) -> shapeMgu te $ (t, t2) : rest
    (_, KindedType t _ _) -> shapeMgu te $ (t1, t) : rest
    (TypeName _ _ v1, TypeAppl f a) -> case redStep t2 of
      Just r2 -> shapeMgu te $ (t1, r2) : rest
      Nothing -> if v1 > 0 then do
             vf <- toPairState $ freshTypeVarT f
             va <- toPairState $ freshTypeVarT a
             let s = Map.singleton v1 (TypeAppl vf va)
             addSubst s
             shapeMgu te $ (vf, f) : (case rawKindOfType vf of
                 FunKind CoVar _ _ _ -> [(va, a)]
                 FunKind ContraVar _ _ _ -> [(a, va)]
                 _ -> [(a, va), (va, a)]) ++ substPairList s tl ++ atoms
       else error ("shapeMgu1a: " ++ showDoc t1 " < " ++ showDoc t2 "")
    (TypeName _ _ v1, _) | absOrExpandedAbs t2 -> if v1 > 0 then do
             let s = Map.singleton v1 t2
             addSubst s
             shapeMgu te $ substPairList s tl ++ atoms
       else error ("shapeMgu1b: " ++ showDoc t1 " < " ++ showDoc t2 "")
    (_, TypeName _ _ _) -> do
      ats <- shapeMgu te ((t2, t1) : map swap rest)
      return $ map swap ats
    (TypeAppl f1 a1, TypeAppl f2 a2) -> let
        (ry1, Result _ ms1) = case redStep t1 of
            Just r1 -> (r1, shapeMatch (typeMap te) r1 t2)
            Nothing -> (t1, fail "shapeMatch1")
        (ry2, Result _ ms2) = case redStep t2 of
            Just r2 -> (r2, shapeMatch (typeMap te) t1 r2)
            Nothing -> (t2, fail "shapeMatch2")
        res = shapeMgu te $ (f1, f2) :
           case (rawKindOfType f1, rawKindOfType f2) of
              (FunKind CoVar _ _ _,
               FunKind CoVar _ _ _) -> (a1, a2) : rest
              (FunKind ContraVar _ _ _,
               FunKind ContraVar _ _ _) -> (a2, a1) : rest
              _ -> (a1, a2) : (a2, a1) : rest
        in case ms1 of
               Nothing -> case ms2 of
                   Nothing -> res
                   Just _ -> shapeMgu te $ (t1, ry2) : rest
               Just _ -> shapeMgu te $ (ry1, t2) : rest
    _ -> if t1 == t2 then shapeMgu te rest else
         error ("shapeMgu2: " ++ showDoc t1 " < " ++ showDoc t2 "")

shapeUnify :: Env -> [(Type, Type)] -> State Int (Subst, [(Type, Type)])
shapeUnify te l = do
    c <- get
    let (r, (n, s)) = runState (shapeMgu te l) (c, eps)
    put n
    return (s, r)

-- input an atomized constraint list
collapser :: Rel.Rel Type -> Result Subst
collapser r =
    let t = Rel.sccOfClosure r
        ks = map (Set.partition ( \ e -> case e of
                                      TypeName _ _ n -> n==0
                                      _ -> error "collapser")) t
        ws = filter (hasMany . fst) ks
    in if null ws then
       return $ foldr ( \ (cs, vs) s ->
               if Set.null cs then
                    extendSubst s $ Set.deleteFindMin vs
               else extendSubst s (Set.findMin cs, vs)) eps ks
    else Result
         (map ( \ (cs, _) ->
                let (c1, rs) = Set.deleteFindMin cs
                    c2 = Set.findMin rs
                in Diag Hint ("contradicting type inclusions for '"
                         ++ showDoc c1 "' and '"
                         ++ showDoc c2 "'") nullRange) ws) Nothing

extendSubst :: Subst -> (Type, Set.Set Type) -> Subst
extendSubst s (t, vs) = Set.fold ( \ (TypeName _ _ n) ->
              Map.insert n t) s vs

-- | partition into qualification and subtyping constraints
partitionC :: Constraints -> (Constraints, Constraints)
partitionC = Set.partition ( \ c -> case c of
                             Kinding _ _ -> True
                             Subtyping _ _ -> False)

-- | convert subtypings constrains to a pair list
toListC :: Constraints -> [(Type, Type)]
toListC l = [ (t1, t2) | Subtyping t1 t2 <- Set.toList l ]

shapeMatchPairList :: TypeMap -> [(Type, Type)] -> Result Subst
shapeMatchPairList tm l = case l of
    [] -> return eps
    (t1, t2) : rt -> do
        s1 <- shapeMatch tm t1 t2
        s2 <- shapeMatchPairList tm $ substPairList s1 rt
        return $ compSubst s1 s2

shapeRel :: Env -> Constraints
         -> State Int (Result (Subst, Constraints, Rel.Rel Type))
shapeRel te cs =
    let (qs, subS) = partitionC cs
        subL = toListC subS
    in case shapeMatchPairList (typeMap te) subL of
       Result ds Nothing -> return $ Result ds Nothing
       _ -> do (s1, atoms) <- shapeUnify te subL
               let r = Rel.transClosure $ Rel.fromList atoms
                   es = Map.foldWithKey ( \ t1 st l1 ->
                             case t1 of
                             TypeName _ _ 0 -> Set.fold ( \ t2 l2 ->
                                 case t2 of
                                 TypeName _ _ 0 -> if lesserType te t1 t2
                                     then l2 else (t1, t2) : l2
                                 _ -> l2) l1 st
                             _ -> l1) [] $ Rel.toMap r
               return $ if null es then
                 case collapser r of
                   Result ds Nothing -> Result ds Nothing
                   Result _ (Just s2) ->
                       let s = compSubst s1 s2
                       in return (s, substC s qs,
                                  Rel.fromList $ substPairList s2 atoms)
                 else Result (map ( \ (t1, t2) ->
                                 mkDiag Hint "rejected" $
                                             Subtyping t1 t2) es) Nothing

-- | compute monotonicity of a type variable
monotonic :: Int -> Type -> (Bool, Bool)
monotonic v = foldType FoldTypeRec
  { foldTypeName = \ _ _ _ i -> (True, i /= v)
  , foldTypeAppl = \ t@(TypeAppl tf _) ~(f1, f2) (a1, a2) ->
      -- avoid evaluation of (f1, f2) if it is not needed by "~"
     case redStep t of
      Just r -> monotonic v r
      Nothing -> case rawKindOfType tf of
        FunKind CoVar _ _ _ -> (f1 && a1, f2 && a2)
        FunKind ContraVar _ _ _ -> (f1 && a2, f2 && a1)
        _ -> (f1 && a1 && a2, f2 && a1 && a2)
  , foldExpandedType = \ _ _ p -> p
  , foldTypeAbs = \ _ _ _ _ -> (False, False)
  , foldKindedType = \ _ p _ _ -> p
  , foldTypeToken = \ _ _ -> error "monotonic.foldTypeToken"
  , foldBracketType = \ _ _ _ _ -> error "monotonic.foldBracketType"
  , foldMixfixType = \ _ -> error "monotonic.foldMixfixType" }

-- | find monotonicity based instantiation
monoSubst :: Rel.Rel Type -> Type -> Subst
monoSubst r t =
    let varSet = Set.fromList . leaves (> 0)
        vs = Set.toList $ Set.union (varSet t) $ Set.unions $ map varSet
              $ Set.toList $ Rel.nodes r
        monos = filter ( \ (i, (n, rk)) -> case monotonic i t of
                                (True, _) -> isSingleton
                                    (Rel.predecessors r $
                                        TypeName n rk i)
                                _ -> False) vs
        antis = filter ( \ (i, (n, rk)) -> case monotonic i t of
                                (_, True) -> isSingleton
                                     (Rel.succs r $
                                         TypeName n rk i)
                                _ -> False) vs
        resta = filter ( \ (i, (n, rk)) -> case monotonic i t of
                                (True, True) -> hasMany $
                                     Rel.succs r $ TypeName n rk i
                                _ -> False) vs
        restb = filter ( \ (i, (n, rk)) -> case monotonic i t of
                                (True, True) -> hasMany $
                                     Rel.predecessors r $ TypeName n rk i
                                _ -> False) vs
    in if null antis then
          if null monos then
             if null resta then
                if null restb then eps else
                    let (i, (n, rk)) = head restb
                        tn = TypeName n rk i
                        s = Rel.predecessors r tn
                        sl = Set.delete tn $ foldl1 Set.intersection
                                      $ map (Rel.succs r)
                                      $ Set.toList s
                    in Map.singleton i $ Set.findMin $ if Set.null sl then s
                       else sl
             else   let (i, (n, rk)) = head resta
                        tn = TypeName n rk i
                        s = Rel.succs r tn
                        sl = Set.delete tn $ foldl1 Set.intersection
                                        $ map (Rel.predecessors r)
                                        $ Set.toList s
                    in Map.singleton i $ Set.findMin $ if Set.null sl then s
                       else sl
          else Map.fromDistinctAscList $ map ( \ (i, (n, rk)) ->
                (i, Set.findMin $ Rel.predecessors r $
                  TypeName n rk i)) monos
       else Map.fromDistinctAscList $ map ( \ (i, (n, rk)) ->
                (i, Set.findMin $ Rel.succs r $
                  TypeName n rk i)) antis

monoSubsts :: Rel.Rel Type -> Type -> Subst
monoSubsts r t =
    let s = monoSubst (Rel.transReduce $ Rel.irreflex r) t in
    if Map.null s then s else
  compSubst s $ monoSubsts (Rel.transClosure $ Rel.map (subst s) r) $ subst s t

-- | Downsets of type variables made monomorphic need to be considered
fromTypeVars :: LocalTypeVars -> Constraints
fromTypeVars = Map.foldWithKey
    (\ t (TypeVarDefn _ vk rk _) c -> case vk of
              Downset ty ->
                insertC (Subtyping (TypeName t rk 0) $ monoType ty) c
              _ -> c) noC

-- | the type relation of declared types
fromTypeMap :: TypeMap -> Rel.Rel Type
fromTypeMap = Map.foldWithKey (\ t ti r -> let k = typeKind ti in
                    Set.fold ( \ j -> Rel.insert (TypeName t k 0)
                                $ TypeName j k 0) r
                                    $ superTypes ti) Rel.empty

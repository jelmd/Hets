{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2003-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  experimental
Portability :  portable

abstract syntax during static analysis
-}

module HasCASL.Le where

import HasCASL.As
import HasCASL.AsUtils
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Common.Lib.State as State
import Common.Result
import Common.Id
import Common.AS_Annotation (Named)
import Common.GlobalAnnotations
import Common.Prec

-- * class info

-- | store the raw kind and all superclasses of a class identifier
data ClassInfo = ClassInfo
    { rawKind :: RawKind
    , classKinds :: [Kind]
    } deriving (Show, Eq)

-- | mapping class identifiers to their definition
type ClassMap = Map.Map ClassId ClassInfo

-- * type info

-- | data type generatedness indicator
data GenKind = Free | Generated | Loose deriving (Show, Eq, Ord)

-- | an analysed alternative with a list of (product) types
data AltDefn =
    Construct (Maybe UninstOpId) [Type] Partiality [[Selector]]
    -- only argument types
    deriving (Show, Eq, Ord)

-- | an analysed component
data Selector =
    Select (Maybe UninstOpId) Type Partiality deriving (Show, Eq, Ord)
    -- only result type

-- | a mapping of type (and disjoint class) identifiers
type IdMap = Map.Map TypeId TypeId

-- | for data types the morphism needs to be kept as well
data DataEntry =
    DataEntry IdMap TypeId GenKind [TypeArg] RawKind [AltDefn]
    deriving (Show, Eq, Ord)

-- | possible definitions for type identifiers
data TypeDefn =
    NoTypeDefn
  | PreDatatype     -- auxiliary entry for DatatypeDefn
  | DatatypeDefn DataEntry
  | AliasTypeDefn TypeScheme
    deriving (Show, Eq)

-- | for type identifiers also store the raw kind, instances and supertypes
data TypeInfo = TypeInfo
    { typeKind :: RawKind
    , otherTypeKinds :: [Kind]
    , superTypes :: Set.Set TypeId
    , typeDefn :: TypeDefn
    } deriving (Show, Eq)

-- | mapping type identifiers to their definition
type TypeMap = Map.Map TypeId TypeInfo

-- | the minimal information for a sort
starTypeInfo :: TypeInfo
starTypeInfo = TypeInfo rStar [universe] Set.empty NoTypeDefn

-- | rename the type according to identifier map (for comorphisms)
mapType :: IdMap -> Type -> Type
mapType m ty = if Map.null m then ty else
    rename ( \ i k n ->
               let t = TypeName i k n in
               if n == 0 then
                  case Map.lookup i m of
                  Just j -> TypeName j k 0
                  _ -> t
               else t) ty

-- * sentences

-- | data types are also special sentences because of their properties
data Sentence =
    Formula Term
  | DatatypeSen [DataEntry]
  | ProgEqSen UninstOpId TypeScheme ProgEq
    deriving (Show, Eq, Ord)

-- * variables

-- | type variable are kept separately
data TypeVarDefn = TypeVarDefn Variance VarKind RawKind Int deriving Show

-- | mapping type variables to their definition
type LocalTypeVars = Map.Map TypeId TypeVarDefn

-- | the type of a local variable
data VarDefn = VarDefn Type deriving Show

-- * assumptions

-- | name and scheme of a constructor
data ConstrInfo = ConstrInfo
    { constrId :: UninstOpId
    , constrType :: TypeScheme
    } deriving (Show, Eq)

-- | possible definitions of functions
data OpDefn =
    NoOpDefn OpBrand
  | ConstructData TypeId     -- ^ target type
  | SelectData [ConstrInfo] TypeId   -- ^ constructors of source type
  | Definition OpBrand Term
    deriving (Show, Eq)

-- | scheme, attributes and definition for function identifiers
data OpInfo = OpInfo
    { opType :: TypeScheme
    , opAttrs :: [OpAttr]
    , opDefn :: OpDefn
    } deriving (Show, Eq)

-- | test for constructor
isConstructor :: OpInfo -> Bool
isConstructor o = case opDefn o of
    ConstructData _ -> True
    _ -> False

-- | a list of infos for overloaded functions
data OpInfos = OpInfos { opInfos :: [OpInfo] } deriving (Show, Eq)

-- | mapping operation identifiers to their definition
type Assumps = Map.Map UninstOpId OpInfos

-- * the local environment and final signature

-- | the signature is established by the classes, types and assumptions
data Env = Env
    { classMap :: ClassMap
    , typeMap :: TypeMap
    , localTypeVars :: LocalTypeVars
    , assumps :: Assumps
    , localVars :: Map.Map Id VarDefn
    , sentences :: [Named Sentence]
    , envDiags :: [Diagnosis]
    , preIds :: (PrecMap, Set.Set Id)
    , globAnnos :: GlobalAnnos
    , counter :: Int
    } deriving Show

-- | the empty environment (fresh variables start with 1)
initialEnv :: Env
initialEnv = Env
    { classMap = Map.empty
    , typeMap = Map.empty
    , localTypeVars = Map.empty
    , assumps = Map.empty
    , localVars = Map.empty
    , sentences = []
    , envDiags = []
    , preIds = (emptyPrecMap, Set.empty)
    , globAnnos = emptyGlobalAnnos
    , counter = 1 }

-- * accessing the environment

-- | add diagnostic messages
addDiags :: [Diagnosis] -> State.State Env ()
addDiags ds = do
    e <- State.get
    State.put $ e {envDiags = reverse ds ++ envDiags e}

-- | add sentences
appendSentences :: [Named Sentence] -> State.State Env ()
appendSentences fs = do
    e <- State.get
    State.put $ e {sentences = reverse fs ++ sentences e}

-- | store a class map
putClassMap :: ClassMap -> State.State Env ()
putClassMap ce = do
    e <- State.get
    State.put e { classMap = ce }

-- | store local assumptions
putLocalVars :: Map.Map Id VarDefn -> State.State Env ()
putLocalVars vs =  do
    e <- State.get
    State.put e { localVars = vs }

-- | converting a result to a state computation
fromResult :: (Env -> Result a) -> State.State Env (Maybe a)
fromResult f = do
   e <- State.get
   let Result ds mr = f e
   addDiags ds
   return mr

-- | store local type variables
putLocalTypeVars :: LocalTypeVars -> State.State Env ()
putLocalTypeVars tvs = do
    e <- State.get
    State.put e { localTypeVars = tvs }

-- | store a complete type map
putTypeMap :: TypeMap -> State.State Env ()
putTypeMap tm = do
    e <- State.get
    State.put e { typeMap = tm }

-- | store assumptions
putAssumps :: Assumps -> State.State Env ()
putAssumps ops = do
    e <- State.get
    State.put e { assumps = ops }

-- | get the variable
getVar :: VarDecl -> Id
getVar(VarDecl v _ _ _) = v

-- | check uniqueness of variables
checkUniqueVars :: [VarDecl] -> State.State Env ()
checkUniqueVars = addDiags . checkUniqueness . map getVar

-- * morphisms

-- mapping qualified operation identifiers (aka renamings)
type FunMap = Map.Map (Id, TypeScheme) (Id, TypeScheme)

-- | keep types and class disjoint and use a single identifier map for both
data Morphism = Morphism
    { msource :: Env
    , mtarget :: Env
    , typeIdMap :: IdMap
    , funMap :: FunMap
    } deriving Show

-- | construct morphism for subsignatures
mkMorphism :: Env -> Env -> Morphism
mkMorphism e1 e2 = Morphism
    { msource = e1
    , mtarget = e2
    , typeIdMap = Map.empty
    , funMap = Map.empty }

-- * symbol stuff

-- | the type or kind of an identifier
data SymbolType a =
    OpAsItemType TypeScheme
  | TypeAsItemType (AnyKind a)
  | ClassAsItemType (AnyKind a)
    deriving (Show, Eq, Ord)

-- | symbols with their type and env (to look up type aliases)
data Symbol =
    Symbol {symName :: Id, symType :: SymbolType (), symEnv :: Env}
    deriving Show

instance Eq Symbol where
    s1 == s2 = compare s1 s2 == EQ

instance Ord Symbol where
    compare s1 s2 = compare (symName s1, symType s1) (symName s2, symType s2)

-- | mapping symbols to symbols
type SymbolMap = Map.Map Symbol Symbol

-- | a set of symbols
type SymbolSet = Set.Set Symbol

-- | create a type symbol
idToTypeSymbol :: Env -> Id -> RawKind -> Symbol
idToTypeSymbol e idt k = Symbol idt (TypeAsItemType k) e

-- | create a class symbol
idToClassSymbol :: Env -> Id -> RawKind -> Symbol
idToClassSymbol e idt k = Symbol idt (ClassAsItemType k) e

-- | create an operation symbol
idToOpSymbol :: Env -> Id -> TypeScheme -> Symbol
idToOpSymbol e idt typ = Symbol idt (OpAsItemType typ) e

-- | raw symbols where the type of a qualified raw symbol is not yet analysed
data RawSymbol =
    AnID Id
  | AKindedId SymbKind Id
  | AQualId Id (SymbolType ClassId)
  | ASymbol Symbol
    deriving (Show, Eq, Ord)

-- | mapping raw symbols to raw symbols
type RawSymbolMap = Map.Map RawSymbol RawSymbol

-- | create a raw symbol from an identifier
idToRaw :: Id -> RawSymbol
idToRaw x = AnID x

-- | extract the top identifer from a raw symbol
rawSymName :: RawSymbol -> Id
rawSymName r = case r of
    AnID i -> i
    AKindedId _ i -> i
    AQualId i _ -> i
    ASymbol s -> symName s

-- | convert a symbol type to a symbol kind
symbTypeToKind :: SymbolType a -> SymbKind
symbTypeToKind s = case s of
    OpAsItemType _ -> SK_op
    TypeAsItemType _ -> SK_type
    ClassAsItemType _ -> SK_class

-- | wrap a symbol as raw symbol (is 'ASymbol')
symbolToRaw :: Symbol -> RawSymbol
symbolToRaw sym = ASymbol sym

-- | create a raw symbol from a symbol kind and an identifier
symbKindToRaw :: SymbKind -> Id -> RawSymbol
symbKindToRaw sk = case sk of
    Implicit -> AnID
    _ -> AKindedId $ case sk of
        SK_pred -> SK_op
        SK_fun -> SK_op
        SK_sort -> SK_type
        _ -> sk

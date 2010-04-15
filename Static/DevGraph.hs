{- |
Module      :  $Header$
Description :  Central datastructures for development graphs
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  till@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable(Logic)

Central datastructures for development graphs
   Follows Sect. IV:4.2 of the CASL Reference Manual.

We also provide functions for constructing and modifying development graphs.
However note that these changes need to be propagated to the GUI if they
also shall be visible in the displayed development graph.
-}

{-
   References:

   T. Mossakowski, S. Autexier and D. Hutter:
   Extending Development Graphs With Hiding.
   H. Hussmann (ed.): Fundamental Approaches to Software Engineering 2001,
   Lecture Notes in Computer Science 2029, p. 269-283,
   Springer-Verlag 2001.

   T. Mossakowski, S. Autexier, D. Hutter, P. Hoffman:
   CASL Proof calculus. In: CASL reference manual, part IV.
   Available from http://www.cofi.info

-}

module Static.DevGraph where

import Syntax.AS_Structured
import Static.GTheory

import Logic.Logic
import Logic.ExtSign
import Logic.Comorphism
import Logic.Grothendieck
import Logic.Prover

import qualified Common.Lib.Rel as Rel
import qualified Common.Lib.Graph as Tree
import qualified Common.Lib.SizedList as SizedList
import qualified Common.OrderedMap as OMap
import Common.AS_Annotation
import Common.GlobalAnnotations
import Common.Id
import Common.Utils (numberSuffix, splitByList)
import Common.LibName
import Common.Consistency

import Control.Concurrent.MVar
import Control.Exception (assert)

import Data.Graph.Inductive.Basic
import Data.Graph.Inductive.Graph as Graph
import Data.Graph.Inductive.Query.DFS
import Data.List
import Data.Maybe
import qualified Data.Map as Map
import qualified Data.Set as Set

-- * types for structured specification analysis

-- ** basic types

-- | Node with signature in a DG
data NodeSig = NodeSig { getNode :: Node, getSig :: G_sign }
    deriving (Show, Eq)

{- | NodeSig or possibly the empty sig in a logic
     (but since we want to avoid lots of vacuous nodes with empty sig,
     we do not assign a real node in the DG here) -}
data MaybeNode = JustNode NodeSig | EmptyNode AnyLogic deriving (Show, Eq)

data BasicConsProof = BasicConsProof deriving (Show, Eq) -- needs more details

-- ** node label types

data XPathPart = ElemName String | ChildIndex Int deriving (Show, Eq, Ord)

{- | name of a node in a DG; auxiliary nodes may have extension string
     and non-zero number (for these, names are usually hidden). -}
data NodeName = NodeName
  { getName :: SIMPLE_ID
  , extString :: String
  , extIndex :: Int
  , xpath :: [XPathPart]
  } deriving (Show, Eq, Ord)


isInternal :: NodeName -> Bool
isInternal n = extIndex n /= 0 || not (null $ extString n)

-- | a wrapper for renamings with a trivial Ord instance
newtype Renamed = Renamed RENAMING deriving Show

instance Ord Renamed where
  compare _ _ = EQ

instance Eq Renamed where
  _ == _ = True

-- | a wrapper for restrictions with a trivial Ord instance
newtype Restricted = Restricted RESTRICTION deriving Show

instance Ord Restricted where
  compare _ _ = EQ

instance Eq Restricted where
  _ == _ = True

{- | Data type indicating the origin of nodes and edges in the input language
     This is not used in the DG calculus, only may be used in the future
     for reconstruction of input and management of change. -}
data DGOrigin =
    DGEmpty
  | DGBasic
  | DGBasicSpec G_basic_spec (Set.Set G_symbol)
  | DGExtension
  | DGLogicCoercion
  | DGTranslation Renamed
  | DGUnion
  | DGRestriction Restricted
  | DGRevealTranslation
  | DGFreeOrCofree FreeOrCofree
  | DGLocal
  | DGClosed
  | DGLogicQual
  | DGData
  | DGFormalParams
  | DGImports
  | DGInst SIMPLE_ID
  | DGFitSpec
  | DGFitView SIMPLE_ID
  | DGProof
  | DGNormalForm Node
  | DGintegratedSCC
  | DGFlattening
    deriving (Show, Eq, Ord)

-- | node content or reference to another library's node
data DGNodeInfo = DGNode
  { node_origin :: DGOrigin       -- origin in input language
  , node_cons_status :: ConsStatus } -- like a link from the empty signature
  | DGRef                        -- reference to node in a different DG
  { ref_libname :: LibName      -- pointer to DG where ref'd node resides
  , ref_node :: Node             -- pointer to ref'd node
  } deriving (Show, Eq)

-- | node inscriptions in development graphs.
-- Nothing entries indicate "not computed yet"
data DGNodeLab =
  DGNodeLab
  { dgn_name :: NodeName        -- name in the input language
  , dgn_theory :: G_theory       -- local theory
  , globalTheory :: Maybe G_theory -- global theory
  , labelHasHiding :: Bool      -- has this node an ingoing hiding link
  , labelHasFree :: Bool        -- has incoming free definition link
  , dgn_nf :: Maybe Node         -- normal form, for Theorem-Hide-Shift
  , dgn_sigma :: Maybe GMorphism -- inclusion of signature into nf signature
  , dgn_freenf :: Maybe Node -- normal form for freeness
  , dgn_phi :: Maybe GMorphism -- morphism from signature to nffree signature
  , nodeInfo :: DGNodeInfo
  , dgn_lock :: Maybe (MVar ())
  , dgn_symbolpathlist :: G_symbolmap [SLinkPath]
  } deriving (Show, Eq)

instance Show (MVar a) where
  show _ = ""

isDGRef :: DGNodeLab -> Bool
isDGRef l = case nodeInfo l of
    DGNode {} -> False
    DGRef {} -> True

hasSenKind :: (forall a . SenStatus a (AnyComorphism, BasicProof) -> Bool)
           -> DGNodeLab -> Bool
hasSenKind f dgn = case dgn_theory dgn of
  G_theory _lid _sigma _ sens _ -> not $ Map.null $ OMap.filter f sens

-- | test if a given node label has local open goals
hasOpenGoals :: DGNodeLab -> Bool
hasOpenGoals = hasSenKind (\ s -> not (isAxiom s) && not (isProvenSenStatus s))

-- | check if the node has an internal name
isInternalNode :: DGNodeLab -> Bool
isInternalNode DGNodeLab {dgn_name = n} = isInternal n

getNodeConsStatus :: DGNodeLab -> ConsStatus
getNodeConsStatus lbl = case nodeInfo lbl of
   DGRef {} -> mkConsStatus None
   DGNode { node_cons_status = c } -> c

getNodeCons :: DGNodeLab -> Conservativity
getNodeCons nl = case getNodeConsStatus nl of
  ConsStatus cons _ _ -> cons

-- | returns the Conservativity if the given node has one, otherwise none
getNodeConservativity :: LNode DGNodeLab -> Conservativity
getNodeConservativity = getNodeCons . snd

-- | test if a node conservativity is open,
-- return input for refs or nodes with normal forms
hasOpenNodeConsStatus :: Bool -> DGNodeLab -> Bool
hasOpenNodeConsStatus b lbl = if isJust $ dgn_nf lbl then b else
  hasOpenConsStatus b $ getNodeConsStatus lbl

markNodeConsistent :: String -> DGNodeLab -> DGNodeLab
markNodeConsistent str dgnode = dgnode
  { nodeInfo = case nodeInfo dgnode of
      ninfo@DGNode { node_cons_status = ConsStatus c pc thm } ->
          if pc >= Cons && isProvenThmLinkStatus thm then ninfo else
          ninfo { node_cons_status = ConsStatus c Cons
                    $ Proven (DGRule $ "Consistency" ++ str) emptyProofBasis }
      ninfo -> ninfo }

markNodeInconsistent :: String -> DGNodeLab -> DGNodeLab
markNodeInconsistent str dgnode = dgnode
  { nodeInfo = case nodeInfo dgnode of
      ninfo@DGNode { node_cons_status = ConsStatus c pc thm } ->
          if pc == Inconsistent && isProvenThmLinkStatus thm then ninfo else
          ninfo { node_cons_status = ConsStatus c Inconsistent
                    $ Proven (DGRule $ "Inconsistency" ++ str) emptyProofBasis }
      ninfo -> ninfo }

-- | test if a conservativity is open, return input for None
hasOpenConsStatus :: Bool -> ConsStatus -> Bool
hasOpenConsStatus b (ConsStatus cons _ thm) = case cons of
    None -> b
    _ -> not $ isProvenThmLinkStatus thm

data DGNodeType = DGNodeType
  { isRefType :: Bool
  , isProvenNode :: Bool
  , isProvenCons :: Bool
  , isInternalSpec :: Bool }
  deriving (Eq, Ord, Show)

-- | creates a DGNodeType from a DGNodeLab
getRealDGNodeType :: DGNodeLab -> DGNodeType
getRealDGNodeType dgnlab = DGNodeType
  { isRefType = isDGRef dgnlab
  , isProvenNode = not $ hasOpenGoals dgnlab
  , isProvenCons = not $ hasOpenNodeConsStatus False dgnlab
  , isInternalSpec = isInternalNode dgnlab }

-- | Creates a list with all DGNodeType types
listDGNodeTypes :: [DGNodeType]
listDGNodeTypes = let bs = [False, True] in
  [ DGNodeType
    { isRefType = ref
    , isProvenNode = isEmpty'
    , isProvenCons = proven
    , isInternalSpec = spec }
  | ref <- bs
  , isEmpty' <- bs
  , proven <- bs
  , spec <- bs ]

-- ** edge label types

{- an edge id used to be represented as a list of ints.
     the reason of an edge can have multiple ids is, for example, there exists
     an proven edge e1 with id 1 and an unproven edge e2 with id 2 between
     two nodes. Now after applying some rules e2 is proven, but it's actually
     the same as the proven edge e1, then the proven e2 should not be inserted
     into the graph again, but e1 will take e2's id 2 because 2 is probably
     saved in some other places. As a result, e1 would have 1 and 2 as its id.
     This type can be extended to a more complicated struture, like a tree
     suggested by Till.
-}

-- | unique number for edges
newtype EdgeId = EdgeId Int deriving (Show, Eq, Ord, Enum)

-- | the first edge in a graph
startEdgeId :: EdgeId
startEdgeId = EdgeId 0

showEdgeId :: EdgeId -> String
showEdgeId (EdgeId i) = show i

-- | a set of used edges
newtype ProofBasis = ProofBasis { proofBasis :: Set.Set EdgeId }
    deriving (Show, Eq, Ord)

-- | a wrapper for fitting morphisms with a trivial Eq instance
newtype Fitted = Fitted [G_mapping] deriving Show

instance Eq Fitted where
  _ == _ = True

data DGLinkOrigin =
    SeeTarget
  | SeeSource
  | DGImpliesLink
  | DGLinkExtension
  | DGLinkTranslation
  | DGLinkClosedLenv
  | DGLinkImports
  | DGLinkMorph SIMPLE_ID
  | DGLinkInst SIMPLE_ID Fitted
  | DGLinkInstArg SIMPLE_ID
  | DGLinkView SIMPLE_ID Fitted
  | DGLinkFitView SIMPLE_ID
  | DGLinkFitViewImp SIMPLE_ID
  | DGLinkProof
  | DGLinkFlatteningUnion
  | DGLinkFlatteningRename
    deriving (Show, Eq)

-- | name of the LinkOrigin if existent
getLinkOriginName :: DGLinkOrigin -> Maybe SIMPLE_ID
getLinkOriginName lo = case lo of
                         DGLinkMorph sid -> Just sid
                         DGLinkInst sid _ -> Just sid
                         DGLinkInstArg sid -> Just sid
                         DGLinkView sid _ -> Just sid
                         DGLinkFitView sid -> Just sid
                         DGLinkFitViewImp sid -> Just sid
                         _ -> Nothing


{- | Rules in the development graph calculus,
   Sect. IV:4.4 of the CASL Reference Manual explains them in depth
   mutual recursive with 'DGLinkLab', 'DGLinkType', and 'ThmLinkStatus'
-}
data DGRule =
    DGRule String
  | DGRuleWithEdge String (LEdge DGLinkLab)
  | DGRuleLocalInference [(String, String)] -- renamed theorems
  | Composition [LEdge DGLinkLab]
  | BasicInference AnyComorphism BasicProof -- coding and proof tree. obsolete?
  | BasicConsInference Edge BasicConsProof
    deriving (Show, Eq)

-- | proof status of a link
data ThmLinkStatus = LeftOpen | Proven DGRule ProofBasis deriving (Show, Eq)

isProvenThmLinkStatus :: ThmLinkStatus -> Bool
isProvenThmLinkStatus tls = case tls of
  LeftOpen -> False
  _ -> True

data Scope = Local | Global deriving (Show, Eq, Ord)

data LinkKind = DefLink | ThmLink ThmLinkStatus deriving (Show, Eq)

data FreeOrCofree = Free | Cofree deriving (Show, Eq, Ord)

data ConsStatus = ConsStatus Conservativity Conservativity ThmLinkStatus
  deriving (Show, Eq)

isProvenConsStatusLink :: ConsStatus -> Bool
isProvenConsStatusLink = not . hasOpenConsStatus False

mkConsStatus :: Conservativity -> ConsStatus
mkConsStatus c = ConsStatus c None LeftOpen

{- | Link types of development graphs,
     Sect. IV:4.2 of the CASL Reference Manual explains them in depth. -}
data DGLinkType =
    ScopedLink Scope LinkKind ConsStatus
  | HidingDefLink
  | FreeOrCofreeDefLink FreeOrCofree MaybeNode -- the "parameter" node
  | HidingFreeOrCofreeThm (Maybe FreeOrCofree) GMorphism ThmLinkStatus
    -- DGLink S1 S2 m2 (DGLinkType m1 p) n
    -- corresponds to a span of morphisms
    -- S1 <--m1-- S --m2--> S2
    deriving (Show, Eq)

-- | extract theorem link status from link type
thmLinkStatus :: DGLinkType -> Maybe ThmLinkStatus
thmLinkStatus t = case t of
    ScopedLink _ (ThmLink s) _ -> Just s
    HidingFreeOrCofreeThm _ _ s -> Just s
    _ -> Nothing

-- | link inscriptions in development graphs
data DGLinkLab = DGLink
  { dgl_morphism :: GMorphism  -- signature morphism of link
  , dgl_type :: DGLinkType     -- type: local, global, def, thm?
  , dgl_origin :: DGLinkOrigin -- origin in input language
  , dglPending :: Bool        -- open proofs of edges in proof basis
  , dgl_id :: EdgeId          -- id of the edge
  , dglName :: NodeName         -- name of the edge
  } deriving (Show, Eq)

mkDGLink :: GMorphism -> DGLinkType -> DGLinkOrigin -> NodeName -> EdgeId
         -> DGLinkLab
mkDGLink mor ty orig nn ei = DGLink
  { dgl_morphism = mor
  , dgl_type = ty
  , dgl_origin = orig
  , dglPending = False
  , dgl_id = ei
  , dglName = nn }

-- | name a link
nameDGLink :: NodeName -> DGLinkLab -> DGLinkLab
nameDGLink nn l = l { dglName = nn }

defDGLink :: GMorphism -> DGLinkType -> DGLinkOrigin -> DGLinkLab
defDGLink m ty orig = let nn = makeName $ case getLinkOriginName orig of
                                            Just sid -> sid
                                            _ -> mkSimpleId ""
                      in mkDGLink m ty orig nn defaultEdgeId

globDefLink :: GMorphism -> DGLinkOrigin -> DGLinkLab
globDefLink m = defDGLink m globalDef

-- | describe the link type of the label
getDGLinkType :: DGLinkLab -> String
getDGLinkType = getDGEdgeTypeName . getRealDGLinkType

-- | converts a DGEdgeType to a String
getDGEdgeTypeName :: DGEdgeType -> String
getDGEdgeTypeName e =
  (if isInc e then (++ "Inc") else id)
  $ getDGEdgeTypeModIncName $ edgeTypeModInc e

getDGEdgeTypeModIncName :: DGEdgeTypeModInc -> String
getDGEdgeTypeModIncName et = case et of
  ThmType thm isPrvn _ _ ->
    let prvn = (if isPrvn then "P" else "Unp") ++ "roven" in
    case thm of
      HidingThm -> prvn ++ "HidingThm"
      FreeOrCofreeThm -> prvn ++ "Thm"
      GlobalOrLocalThm scope isHom ->
          let het = if isHom then id else ("Het" ++) in
          het (case scope of
                 Local -> "Local"
                 Global -> if isHom then "Global" else "") ++ prvn ++ "Thm"
  FreeOrCofreeDef -> "Def"
  _ -> show et

data DGEdgeType = DGEdgeType
  { edgeTypeModInc :: DGEdgeTypeModInc
  , isInc :: Bool }
  deriving (Eq, Ord, Show)

data DGEdgeTypeModInc =
    GlobalDef
  | HetDef
  | HidingDef
  | LocalDef
  | FreeOrCofreeDef -- free or cofree
  | ThmType { thmEdgeType :: ThmTypes
            , isProvenEdge :: Bool
            , isConservativ :: Bool
            , isPending :: Bool }
  deriving (Eq, Ord, Show)

data ThmTypes =
    HidingThm
  | FreeOrCofreeThm
  | GlobalOrLocalThm { isLocalThmType :: Scope
                     , isHomThm :: Bool }
  deriving (Eq, Ord, Show)

getHomEdgeType :: Bool -> Bool -> DGLinkType -> DGEdgeTypeModInc
getHomEdgeType isPend isHom lt = case lt of
      ScopedLink scope lk cons -> case lk of
          DefLink -> case scope of
            Local -> LocalDef
            Global -> if isHom then GlobalDef else HetDef
          ThmLink st -> ThmType
            { thmEdgeType = GlobalOrLocalThm scope isHom
            , isProvenEdge = isProvenThmLinkStatus st
            , isConservativ = isProvenConsStatusLink cons
            , isPending = isPend } -- needs to be checked
      HidingDefLink -> HidingDef
      FreeOrCofreeDefLink _ _ -> FreeOrCofreeDef
      HidingFreeOrCofreeThm mh _ st -> ThmType
        { thmEdgeType = case mh of
            Nothing -> HidingThm
            _ -> FreeOrCofreeThm
        , isProvenEdge = isProvenThmLinkStatus st
        , isConservativ = True
        , isPending = isPend }

-- | creates a DGEdgeType from a DGLinkLab
getRealDGLinkType :: DGLinkLab -> DGEdgeType
getRealDGLinkType lnk = let
  gmor = dgl_morphism lnk
  in DGEdgeType
  { edgeTypeModInc = getHomEdgeType (dglPending lnk) (isHomogeneous gmor)
      $ dgl_type lnk
  , isInc = case gmor of
      GMorphism cid _ _ mor _ -> isInclusionComorphism cid && isInclusion mor
  }

-- | Creates a list with all DGEdgeType types
listDGEdgeTypes :: [DGEdgeType]
listDGEdgeTypes =
  [ DGEdgeType { edgeTypeModInc = modinc
               , isInc = isInclusion' }
  | modinc <-
    [ GlobalDef
    , HetDef
    , HidingDef
    , LocalDef
    , FreeOrCofreeDef ] ++
      [ ThmType { thmEdgeType = thmType
                , isProvenEdge = proven
                , isConservativ = cons
                , isPending = pending }
      | thmType <-
        [ HidingThm
        , FreeOrCofreeThm] ++
          [ GlobalOrLocalThm { isLocalThmType = local
                             , isHomThm = hom }
          | local <- [Local, Global]
          , hom <- [True, False]
          ]
      , proven <- [True, False]
      , cons <- [True, False]
      , pending <- [True, False]
      ]
  , isInclusion' <- [True, False]
  ]

-- ** types for global environments

-- | import, formal parameters and united signature of formal params
data GenSig = GenSig MaybeNode [NodeSig] MaybeNode deriving Show

-- | genericity and body
data ExtGenSig = ExtGenSig GenSig NodeSig deriving Show

-- | source, morphism, parameterized target
data ExtViewSig = ExtViewSig NodeSig GMorphism ExtGenSig deriving Show

{- ** types for architectural and unit specification analysis
    (as defined for basic static semantics in Chap. III:5.1) -}

data UnitSig = UnitSig [NodeSig] NodeSig deriving Show

data ImpUnitSigOrSig = ImpUnitSig MaybeNode UnitSig | Sig NodeSig deriving Show

type StUnitCtx = Map.Map SIMPLE_ID ImpUnitSigOrSig

emptyStUnitCtx :: StUnitCtx
emptyStUnitCtx = Map.empty

data ArchSig = ArchSig StUnitCtx UnitSig deriving Show

-- | an entry of the global environment
data GlobalEntry =
    SpecEntry ExtGenSig
  | ViewEntry ExtViewSig
  | ArchEntry ArchSig
  | UnitEntry UnitSig
  | RefEntry
    deriving Show

type GlobalEnv = Map.Map SIMPLE_ID GlobalEntry

-- ** change and history types

-- | the edit operations of the DGraph
data DGChange =
    InsertNode (LNode DGNodeLab)
  | DeleteNode (LNode DGNodeLab)
  | InsertEdge (LEdge DGLinkLab)
  | DeleteEdge (LEdge DGLinkLab)
  -- it contains the old label and new label with node
  | SetNodeLab DGNodeLab (LNode DGNodeLab)
  deriving (Show, Eq)

data HistElem =
    HistElem DGChange
  | HistGroup DGRule ProofHistory
    deriving (Show, Eq)

type ProofHistory = SizedList.SizedList HistElem

{- | the actual development graph with auxiliary information. A
  'G_sign' should be stored in 'sigMap' under its 'gSignSelfIdx'. The
  same applies to 'G_morphism' with 'morMap' and 'gMorphismSelfIdx'
  resp. 'G_theory' with 'thMap' and 'gTheorySelfIdx'. -}
data DGraph = DGraph
  { globalAnnos :: GlobalAnnos -- ^ global annos of library
  , globalEnv :: GlobalEnv -- ^ name entities (specs, views) of a library
  , dgBody :: Tree.Gr DGNodeLab DGLinkLab  -- ^ actual 'DGraph` tree
  , getNewEdgeId :: EdgeId  -- ^ edge counter
  , refNodes :: Map.Map Node (LibName, Node) -- ^ unexpanded 'DGRef's
  , allRefNodes :: Map.Map (LibName, Node) Node -- ^ all DGRef's
  , sigMap :: Map.Map SigId G_sign -- ^ signature map
  , thMap :: Map.Map ThId G_theory -- ^ morphism map
  , morMap :: Map.Map MorId G_morphism -- ^ theory map
  , proofHistory :: ProofHistory -- ^ applied proof steps
  , redoHistory :: ProofHistory -- ^ undone proofs steps
  , openlock :: Maybe (MVar ())
  -- ^ control of graph display
  } deriving Show

emptyDG :: DGraph
emptyDG = DGraph
  { globalAnnos = emptyGlobalAnnos
  , globalEnv = Map.empty
  , dgBody = Graph.empty
  , getNewEdgeId = startEdgeId
  , refNodes = Map.empty
  , allRefNodes = Map.empty
  , sigMap = Map.empty
  , thMap = Map.empty
  , morMap = Map.empty
  , proofHistory = SizedList.empty
  , redoHistory = SizedList.empty
  , openlock = Nothing }

type LibEnv = Map.Map LibName DGraph

-- | an empty environment
emptyLibEnv :: LibEnv
emptyLibEnv = Map.empty

emptyDGwithMVar :: IO DGraph
emptyDGwithMVar = do
  ol <- newEmptyMVar
  return $ emptyDG { openlock = Just ol }

-- * utility functions

-- ** for node signatures

emptyG_sign :: AnyLogic -> G_sign
emptyG_sign (Logic lid) = G_sign lid (ext_empty_signature lid) startSigId

getMaybeSig :: MaybeNode -> G_sign
getMaybeSig (JustNode ns) = getSig ns
getMaybeSig (EmptyNode l) = emptyG_sign l

getLogic :: MaybeNode -> AnyLogic
getLogic (JustNode ns) = getNodeLogic ns
getLogic (EmptyNode l) = l

getNodeLogic :: NodeSig -> AnyLogic
getNodeLogic (NodeSig _ (G_sign lid _ _)) = Logic lid

-- ** for node names

emptyNodeName :: NodeName
emptyNodeName = NodeName (mkSimpleId "") "" 0 []

showExt :: NodeName -> String
showExt n = let i = extIndex n in extString n ++ if i == 0 then "" else show i

showName :: NodeName -> String
showName n = let ext = showExt n in
    tokStr (getName n) ++ if null ext then ext else "__" ++ ext

makeName :: SIMPLE_ID -> NodeName
makeName n = NodeName n "" 0 [ElemName $ tokStr n]

parseNodeName :: String -> NodeName
parseNodeName s = case splitByList "__" s of
                    [i] ->
                        makeName $ mkSimpleId i
                    [i, e] ->
                        let n = makeName $ mkSimpleId i
                            mSf = numberSuffix e
                            (es, sf) = fromMaybe (e, 0) mSf
                        in n { extString = es
                             , extIndex = sf }
                    _ ->
                        error
                        $ "parseNodeName: malformed NodeName, too many __: "
                              ++ s

incBy :: Int -> NodeName -> NodeName
incBy i n = n
  { extIndex = extIndex n + i
  , xpath = case xpath n of
              ChildIndex j : r -> ChildIndex (j + i) : r
              l -> ChildIndex i : l }

inc :: NodeName -> NodeName
inc = incBy 1

extName :: String -> NodeName -> NodeName
extName s n = n
  { extString = showExt n ++ take 1 s
  , extIndex = 0
  , xpath = ElemName s : xpath n }

-- ** accessing node label

-- | get the origin of a non-reference node (partial)
dgn_origin :: DGNodeLab -> DGOrigin
dgn_origin = node_origin . nodeInfo

-- | get the referenced library (partial)
dgn_libname :: DGNodeLab -> LibName
dgn_libname = ref_libname . nodeInfo

-- | get the referenced node (partial)
dgn_node :: DGNodeLab -> Node
dgn_node = ref_node . nodeInfo

-- | get the signature of a node's theory (total)
dgn_sign :: DGNodeLab -> G_sign
dgn_sign dn = case dgn_theory dn of
    G_theory lid sig ind _ _ -> G_sign lid sig ind

-- | gets the name of a development graph node as a string (total)
getDGNodeName :: DGNodeLab -> String
getDGNodeName = showName . dgn_name

-- | gets the name of a development graph link as a string (total)
getDGLinkName :: DGLinkLab -> String
getDGLinkName = showName . dglName

-- ** creating node content and label

-- | create default content
newNodeInfo :: DGOrigin -> DGNodeInfo
newNodeInfo orig = DGNode
  { node_origin = orig
  , node_cons_status = mkConsStatus None }

-- | create a reference node part
newRefInfo :: LibName -> Node -> DGNodeInfo
newRefInfo ln n = DGRef
  { ref_libname = ln
  , ref_node = n }

-- | create a new node label
newInfoNodeLab :: NodeName -> DGNodeInfo -> G_theory -> DGNodeLab
newInfoNodeLab name info gTh@(G_theory lid _ _ _ _) = DGNodeLab
  { dgn_name = name
  , dgn_theory = gTh
  , globalTheory = Nothing
  , labelHasHiding = False
  , labelHasFree = False
  , dgn_nf = Nothing
  , dgn_sigma = Nothing
  , dgn_freenf = Nothing
  , dgn_phi = Nothing
  , nodeInfo = info
  , dgn_lock = Nothing
  , dgn_symbolpathlist = G_symbolmap lid Map.empty }

-- | create a new node label using 'newNodeInfo' and 'newInfoNodeLab'
newNodeLab :: NodeName -> DGOrigin -> G_theory -> DGNodeLab
newNodeLab name = newInfoNodeLab name . newNodeInfo

-- ** handle the lock of a node

-- | wrapper to access the maybe lock
treatNodeLock :: (MVar () -> a) -> DGNodeLab -> a
treatNodeLock f = maybe (error "MVar not initialised") f . dgn_lock

{- | Acquire the local lock. If already locked it waits till it is unlocked
     again. -}
lockLocal :: DGNodeLab -> IO ()
lockLocal = treatNodeLock $ flip putMVar ()

-- | Tries to acquire the local lock. Return False if already acquired.
tryLockLocal :: DGNodeLab -> IO Bool
tryLockLocal = treatNodeLock $ flip tryPutMVar ()

-- | Releases the local lock.
unlockLocal :: DGNodeLab -> IO ()
unlockLocal = treatNodeLock $ \ lock ->
  tryTakeMVar lock >>= maybe (error "Local lock wasn't locked.") return

-- | checks if locking MVar is initialized
hasLock :: DGNodeLab -> Bool
hasLock = isJust . dgn_lock

-- ** handle edge numbers and proof bases

-- | create a default ID which has to be changed when inserting a certain edge.
defaultEdgeId :: EdgeId
defaultEdgeId = EdgeId (-1)

emptyProofBasis :: ProofBasis
emptyProofBasis = ProofBasis Set.empty

nullProofBasis :: ProofBasis -> Bool
nullProofBasis = Set.null . proofBasis

addEdgeId :: ProofBasis -> EdgeId -> ProofBasis
addEdgeId (ProofBasis s) e = ProofBasis $ Set.insert e s

-- | checks if the given edge is contained in the given proof basis..
roughElem :: LEdge DGLinkLab -> ProofBasis -> Bool
roughElem (_, _, label) = Set.member (dgl_id label) . proofBasis

-- ** edge label equalities

-- | equality without comparing the edge ids
eqDGLinkLabContent :: DGLinkLab -> DGLinkLab -> Bool
eqDGLinkLabContent l1 l2 = let
    i1 = dgl_id l1
    i2 = dgl_id l2
  in if i1 <= defaultEdgeId || i2 <= defaultEdgeId then
    dgl_morphism l1 == dgl_morphism l2
  && dgl_type l1 == dgl_type l2
  && dgl_origin l1 == dgl_origin l2
  && dglName l1 == dglName l2
  else let r = eqDGLinkLabContent l1 l2 { dgl_id = defaultEdgeId}
           s = i1 == i2
       in assert (r == s) s

-- | equality comparing ids only
eqDGLinkLabById :: DGLinkLab -> DGLinkLab -> Bool
eqDGLinkLabById l1 l2 = let
    i1 = dgl_id l1
    i2 = dgl_id l2
    in if i1 > defaultEdgeId && i2 > defaultEdgeId then i1 == i2 else
       error "eqDGLinkLabById"

-- ** setting index maps

{- these index maps should be global for all libraries,
   therefore their contents need to be copied -}
cpIndexMaps :: DGraph -> DGraph -> DGraph
cpIndexMaps from to =
  to { sigMap = sigMap from
     , thMap = thMap from
     , morMap = morMap from }

setSigMapDG :: Map.Map SigId G_sign -> DGraph -> DGraph
setSigMapDG m dg = dg { sigMap = m }

setThMapDG :: Map.Map ThId G_theory -> DGraph -> DGraph
setThMapDG m dg = dg { thMap = m }

setMorMapDG :: Map.Map MorId G_morphism -> DGraph -> DGraph
setMorMapDG m dg = dg { morMap = m }

-- ** looking up in index maps

lookupSigMapDG :: SigId -> DGraph -> Maybe G_sign
lookupSigMapDG i = Map.lookup i . sigMap

lookupThMapDG :: ThId -> DGraph -> Maybe G_theory
lookupThMapDG i = Map.lookup i . thMap

lookupMorMapDG :: MorId -> DGraph -> Maybe G_morphism
lookupMorMapDG i = Map.lookup i . morMap

-- ** getting index maps and their maximal index

getMapAndMaxIndex :: Ord k => k -> (b -> Map.Map k a) -> b -> (Map.Map k a, k)
getMapAndMaxIndex c f gctx =
    let m = f gctx in (m, if Map.null m then c else fst $ Map.findMax m)

sigMapI :: DGraph -> (Map.Map SigId G_sign, SigId)
sigMapI = getMapAndMaxIndex startSigId sigMap

thMapI :: DGraph -> (Map.Map ThId G_theory, ThId)
thMapI = getMapAndMaxIndex startThId thMap

morMapI :: DGraph -> (Map.Map MorId G_morphism, MorId)
morMapI = getMapAndMaxIndex startMorId morMap

-- ** lookup other graph parts

lookupGlobalEnvDG :: SIMPLE_ID -> DGraph -> Maybe GlobalEntry
lookupGlobalEnvDG sid = Map.lookup sid . globalEnv

-- | lookup a referenced library and node of a given reference node
lookupInRefNodesDG :: Node -> DGraph -> Maybe (LibName, Node)
lookupInRefNodesDG n = Map.lookup n . refNodes

-- | lookup a reference node for a given libname and node
lookupInAllRefNodesDG :: DGNodeInfo -> DGraph -> Maybe Node
lookupInAllRefNodesDG ref dg = case ref of
    DGRef { ref_libname = libn, ref_node = refn } ->
        Map.lookup (libn, refn) $ allRefNodes dg
    _ -> Nothing


-- ** lookup nodes by their names or other properties

-- | lookup a node in the graph with a predicate.
lookupNodeWith :: (LNode DGNodeLab -> Bool) -> DGraph
               -> Maybe (LNode DGNodeLab)
lookupNodeWith f dg = find f $ labNodesDG dg

-- | lookup a node in the graph by its name, using showName
-- to convert nodenames. See also 'getDGNodesByName'.
lookupNodeByName :: String -> DGraph -> Maybe (LNode DGNodeLab)
lookupNodeByName s dg = lookupNodeWith f dg where
    f (_, lbl) = getDGNodeName lbl == s


-- ** treat reference nodes

-- | add a new referenced node into the refNodes map of the given DG
addToRefNodesDG :: Node -> DGNodeInfo -> DGraph -> DGraph
addToRefNodesDG n ref dg = case ref of
    DGRef { ref_libname = libn, ref_node = refn } ->
      dg { refNodes = Map.insert n (libn, refn) $ refNodes dg
         , allRefNodes = Map.insert (libn, refn) n $ allRefNodes dg }
    _ -> dg

-- | delete the given referenced node out of the refnodes map
deleteFromRefNodesDG :: Node -> DGraph -> DGraph
deleteFromRefNodesDG n dg = dg { refNodes = Map.delete n $ refNodes dg }

-- ** accessing the actual graph

-- | get the next available node id
getNewNodeDG :: DGraph -> Node
getNewNodeDG = Tree.getNewNode . dgBody

-- | get all the nodes
labNodesDG :: DGraph -> [LNode DGNodeLab]
labNodesDG = labNodes . dgBody

-- | get all the edges
labEdgesDG :: DGraph -> [LEdge DGLinkLab]
labEdgesDG = labEdges . dgBody

-- | checks if a DG is empty or not.
isEmptyDG :: DGraph -> Bool
isEmptyDG = isEmpty . dgBody

-- | checks if a given node belongs to a given DG
gelemDG :: Node -> DGraph -> Bool
gelemDG n = gelem n . dgBody

-- | get the number of nodes of a given DG
noNodesDG :: DGraph -> Int
noNodesDG = noNodes . dgBody

-- | get all nodes which links to the given node in a given DG
preDG :: DGraph -> Node -> [Node]
preDG = pre . dgBody

-- | get all the incoming ledges of the given node in a given DG
innDG :: DGraph -> Node -> [LEdge DGLinkLab]
innDG = inn . dgBody

-- | get all the outgoing ledges of the given node in a given DG
outDG :: DGraph -> Node -> [LEdge DGLinkLab]
outDG = out . dgBody

-- | get all the nodes of the given DG
nodesDG :: DGraph -> [Node]
nodesDG = nodes . dgBody

-- | get all the edges of the given DG
edgesDG :: DGraph -> [Edge]
edgesDG = edges . dgBody

-- | tries to get the label of the given node in a given DG
labDG :: DGraph -> Node -> DGNodeLab
labDG dg = fromMaybe (error "labDG") . lab (dgBody dg)

-- | get the name of a node from the number of node
getNameOfNode :: Node -> DGraph -> String
getNameOfNode index gc = getDGNodeName $ labDG gc index

-- | gets the given number of new node-ids in a given DG.
newNodesDG :: Int -> DGraph -> [Node]
newNodesDG n = newNodes n . dgBody

-- ** decompose the actual graph

-- | tear the given DGraph appart.
matchDG :: Node -> DGraph -> (MContext DGNodeLab DGLinkLab, DGraph)
matchDG n dg = let (mc, b) = match n $ dgBody dg in (mc, dg { dgBody = b })

-- | get the context of the given DG
contextDG :: DGraph -> Node -> Context DGNodeLab DGLinkLab
contextDG = context . dgBody

-- | safe context for graphs
safeContext :: (Show a, Show b, Graph gr) => String -> gr a b -> Node
            -> Context a b
safeContext err g v =
  fromMaybe (error $ err ++ ": Match Exception, Node: " ++ show v)
  . fst $ match v g

-- | get the context and throw input string as error message
safeContextDG :: String -> DGraph -> Node -> Context DGNodeLab DGLinkLab
safeContextDG s = safeContext s . dgBody

-- ** manipulate graph

-- | sets the node with new label and returns the new graph and the old label
labelNodeDG :: LNode DGNodeLab -> DGraph -> (DGraph, DGNodeLab)
labelNodeDG p g =
    let (b, l) = Tree.labelNode p $ dgBody g in (g { dgBody = b }, l)

-- | delete the node out of the given DG
delNodeDG :: Node -> DGraph -> DGraph
delNodeDG n dg = dg { dgBody = delNode n $ dgBody dg }

-- | delete the LNode out of the given DG
delLNodeDG :: LNode DGNodeLab -> DGraph -> DGraph
delLNodeDG n dg = dg { dgBody = Tree.delLNode (==) n $ dgBody dg }

-- | delete a list of nodes out of the given DG
delNodesDG :: [Node] -> DGraph -> DGraph
delNodesDG ns dg = dg { dgBody = delNodes ns $ dgBody dg }

-- | insert a new node into given DGraph
insNodeDG :: LNode DGNodeLab -> DGraph -> DGraph
insNodeDG n dg = dg { dgBody = insNode n $ dgBody dg }

-- | inserts a lnode into a given DG
insLNodeDG :: LNode DGNodeLab -> DGraph -> DGraph
insLNodeDG n@(v, _) g =
    if gelemDG v g then error $ "insLNodeDG " ++ show v else insNodeDG n g

-- | insert a new node with the given node content into a given DGraph
insNodesDG :: [LNode DGNodeLab] -> DGraph -> DGraph
insNodesDG ns dg = dg { dgBody = insNodes ns $ dgBody dg }

-- | delete an edge out of a given DG
delEdgeDG :: Edge -> DGraph -> DGraph
delEdgeDG e dg = dg { dgBody = delEdge e $ dgBody dg }

-- | delete a list of edges
delEdgesDG :: [Edge] -> DGraph -> DGraph
delEdgesDG es dg = dg { dgBody = delEdges es $ dgBody dg }

-- | delete a labeled edge out of the given DG
delLEdgeDG :: LEdge DGLinkLab -> DGraph -> DGraph
delLEdgeDG e g = g
    { dgBody = Tree.delLEdge (\ l1 l2 -> compare (dgl_id l1) $ dgl_id l2) e
      $ dgBody g }

-- | insert a labeled edge into a given DG, return possibly new id of edge
insLEdgeDG :: LEdge DGLinkLab -> DGraph -> (LEdge DGLinkLab, DGraph)
insLEdgeDG (s, t, l) g =
  let eId = dgl_id l
      nId = getNewEdgeId g
      newId = eId == defaultEdgeId
      e = (s, t, if newId then l { dgl_id = nId } else l)
  in (e, g
    { getNewEdgeId = if newId then succ nId else max nId $ succ eId
    , dgBody = fst $ Tree.insLEdge True (\ l1 l2 ->
        if eqDGLinkLabContent l1 { dgl_id = defaultEdgeId } l2
        then EQ else compare (dgl_id l1) $ dgl_id l2) e $ dgBody g })

{- | tries to insert a labeled edge into a given DG, but if this edge
     already exists, then does nothing. -}
insLEdgeNubDG :: LEdge DGLinkLab -> DGraph -> DGraph
insLEdgeNubDG (v, w, l) g =
  let oldEdgeId = getNewEdgeId g
      (ng, change) = Tree.insLEdge False (\ l1 l2 ->
        if eqDGLinkLabContent l1 { dgl_id = defaultEdgeId } l2
        then EQ else compare (dgl_id l1) $ dgl_id l2)
        (v, w, l { dgl_id = oldEdgeId }) $ dgBody g
  in
     g { getNewEdgeId = if change then succ oldEdgeId else oldEdgeId
       , dgBody = ng }

{- | insert an edge into the given DGraph, which updates
     the graph body and the edge counter as well. -}
insEdgeDG :: LEdge DGLinkLab -> DGraph -> DGraph
insEdgeDG l oldDG =
  oldDG { dgBody = insEdge l $ dgBody oldDG
        , getNewEdgeId = succ $ getNewEdgeId oldDG }

-- | insert a list of labeled edge into a given DG
insEdgesDG :: [LEdge DGLinkLab] -> DGraph -> DGraph
insEdgesDG = flip $ foldr insLEdgeNubDG

-- | merge a list of lnodes and ledges into a given DG
mkGraphDG :: [LNode DGNodeLab] -> [LEdge DGLinkLab] -> DGraph -> DGraph
mkGraphDG ns ls = insEdgesDG ls . insNodesDG ns

-- | get nodes by name
getDGNodesByName :: (NodeName -> Bool) -> DGraph -> [LNode DGNodeLab]
getDGNodesByName p = filter (p . dgn_name . snd) . labNodesDG

-- | get links by name (inefficiently)
getDGLinksByName :: (NodeName -> Bool) -> DGraph -> [LEdge DGLinkLab]
getDGLinksByName p = filter (\ (_, _, l) -> p $ dglName l) . labEdgesDG

-- ** top-level functions

-- | initializes the MVar for locking if nessesary
initLocking :: DGraph -> LNode DGNodeLab -> IO (DGraph, DGNodeLab)
initLocking dg (node, dgn) = do
  lock <- newEmptyMVar
  let dgn' = dgn { dgn_lock = Just lock }
  return (fst $ labelNodeDG (node, dgn') dg, dgn')

-- | returns the DGraph that belongs to the given library name
lookupDGraph :: LibName -> LibEnv -> DGraph
lookupDGraph ln = Map.findWithDefault (error $ "lookupDGraph " ++ show ln) ln

{- | compute the theory of a given node.
   If this node is a DGRef, the referenced node is looked up first. -}
computeLocalTheory :: Monad m => LibEnv -> LibName -> Node -> m G_theory
computeLocalTheory libEnv ln =
  computeLocalNodeTheory libEnv $ lookupDGraph ln libEnv

computeLocalNodeTheory :: Monad m => LibEnv -> DGraph -> Node -> m G_theory
computeLocalNodeTheory libEnv dg = computeLocalLabelTheory libEnv . labDG dg

computeLocalLabelTheory :: Monad m => LibEnv -> DGNodeLab -> m G_theory
computeLocalLabelTheory libEnv nodeLab =
  if isDGRef nodeLab
    then
      computeLocalTheory libEnv (dgn_libname nodeLab) $ dgn_node nodeLab
    else return $ dgn_theory nodeLab

-- ** test link types

liftE :: (DGLinkType -> Bool) -> LEdge DGLinkLab -> Bool
liftE f (_, _, edgeLab) = f $ dgl_type edgeLab

-- | or two predicates
liftOr :: (a -> Bool) -> (a -> Bool) -> a -> Bool
liftOr f g x = f x || g x

isGlobalDef :: DGLinkType -> Bool
isGlobalDef lt = case lt of
    ScopedLink Global DefLink _ -> True
    _ -> False

isLocalDef :: DGLinkType -> Bool
isLocalDef lt = case lt of
    ScopedLink Local DefLink _ -> True
    _ -> False

isHidingDef :: DGLinkType -> Bool
isHidingDef lt = case lt of
    HidingDefLink -> True
    _ -> False

isDefEdge :: DGLinkType -> Bool
isDefEdge edge = case edge of
    ScopedLink _ DefLink _ -> True
    HidingDefLink -> True
    FreeOrCofreeDefLink _ _ -> True
    _ -> False

isLocalEdge :: DGLinkType -> Bool
isLocalEdge edge = case edge of
    ScopedLink Local _ _ -> True
    _ -> False

isHidingEdge :: DGLinkType -> Bool
isHidingEdge edge = case edge of
    HidingDefLink -> True
    HidingFreeOrCofreeThm Nothing _ _ -> True
    _ -> False

-- ** create link types

hidingThm :: GMorphism -> DGLinkType
hidingThm m = HidingFreeOrCofreeThm Nothing m LeftOpen

globalThm :: DGLinkType
globalThm = localOrGlobalThm Global None

localThm :: DGLinkType
localThm = localOrGlobalThm Local None

globalConsThm :: Conservativity -> DGLinkType
globalConsThm = localOrGlobalThm Global

localConsThm :: Conservativity -> DGLinkType
localConsThm = localOrGlobalThm Local

localOrGlobalThm :: Scope -> Conservativity -> DGLinkType
localOrGlobalThm sc = ScopedLink sc (ThmLink LeftOpen) . mkConsStatus

localOrGlobalDef :: Scope -> Conservativity -> DGLinkType
localOrGlobalDef sc = ScopedLink sc DefLink . mkConsStatus

globalConsDef :: Conservativity -> DGLinkType
globalConsDef = localOrGlobalDef Global

globalDef :: DGLinkType
globalDef = localOrGlobalDef Global None

localDef :: DGLinkType
localDef = localOrGlobalDef Local None

-- ** link conservativity

getLinkConsStatus :: DGLinkType -> ConsStatus
getLinkConsStatus lt = case lt of
  ScopedLink _ _ c -> c
  _ -> mkConsStatus None

getCons :: DGLinkType -> Conservativity
getCons lt = case getLinkConsStatus lt of
  ConsStatus cons _ _ -> cons

-- | returns the Conservativity if the given edge has one, otherwise none
getConservativity :: LEdge DGLinkLab -> Conservativity
getConservativity (_, _, edgeLab) = getCons $ dgl_type edgeLab

-- | returns the conservativity of the given path
getConservativityOfPath :: [LEdge DGLinkLab] -> Conservativity
getConservativityOfPath path = minimum [getConservativity e | e <- path]

-- * bottom up traversal

-- | Creates a LibName relation wrt dependencies via reference nodes
getLibDepRel :: LibEnv -> Rel.Rel LibName
getLibDepRel = Rel.transClosure
  . Rel.fromSet . Map.foldWithKey (\ ln dg s ->
    foldr ((\ x -> if isDGRef x then Set.insert (ln, dgn_libname x) else id)
           . snd) s $ labNodesDG dg) Set.empty

topsortedLibsWithImports :: Rel.Rel LibName -> [LibName]
topsortedLibsWithImports = concatMap Set.toList . Rel.topSort

getTopsortedLibs :: LibEnv -> [LibName]
getTopsortedLibs le = let
  rel = getLibDepRel le
  ls = reverse $ topsortedLibsWithImports rel
  restLs = Set.toList $ Set.difference (Map.keysSet le) $ Rel.nodes rel
  in ls ++ restLs

{- | Get imported libs in topological order, i.e.  lib(s) without imports first.
     The input lib-name will be last -}
dependentLibs :: LibName -> LibEnv -> [LibName]
dependentLibs ln le =
  let rel = getLibDepRel le
      ts = topsortedLibsWithImports rel
      is = Set.toList (Rel.succs rel ln)
  in reverse $ ln : intersect ts is

topsortedNodes :: DGraph -> [LNode DGNodeLab]
topsortedNodes dgraph = let dg = dgBody dgraph in
  reverse $ postorderF $ dffWith (\ (_, n, nl, _) -> (n, nl)) (nodes dg)
    $ efilter (\ (s, t, el) -> s /= t && isDefEdge (dgl_type el)) dg

changedPendingEdges :: DGraph -> [LEdge DGLinkLab]
changedPendingEdges dg = let
  ls = filter (liftE $ not . isDefEdge) $ labEdgesDG dg
  (ms, ps) = foldr (\ (s, t, l) (m, es) ->
       let b = dglPending l
           e = dgl_id l
       in (Map.insert e
          (b, s, t,
          maybe Set.empty (\ ts -> case ts of
             LeftOpen -> Set.empty
             Proven _ pb -> proofBasis pb) . thmLinkStatus $ dgl_type l) m
       , if b && isLocalEdge (dgl_type l) then Set.insert e es else es))
    (Map.empty, Set.empty) ls
  close known =
      let nxt = Map.keysSet $ Map.filter
                (\ (_, _, _, s) -> not $ Set.null $ Set.intersection s known)
                ms
          new = Set.union nxt known
      in if new == known then new else close new
  aPs = close ps
  in filter (\ (_, _, l) -> dglPending l /= Set.member (dgl_id l) aPs) ls

changedLocalTheorems :: DGraph -> LNode DGNodeLab -> [LEdge DGLinkLab]
changedLocalTheorems dg (v, lbl) =
  case dgn_theory lbl of
    G_theory _ _ _ sens _ ->
      foldr (\ e@(_, _, el) l ->
        let pend = dglPending el
            psens = Map.keysSet $ OMap.filter isProvenSenStatus sens
        in case thmLinkStatus $ dgl_type el of
        Just (Proven (DGRuleLocalInference nms) _) | pend
          == Set.isSubsetOf (Set.fromList $ map snd nms) psens -> e : l
        _ -> l
         ) []
      $ filter (liftE $ \ e -> isLocalEdge e && not (isLocalDef e))
      $ innDG dg v

duplicateDefEdges :: DGraph -> [Edge]
duplicateDefEdges = concat .
  filter (not . isSingle) . group . map (\ (s, t, _) -> (s, t))
  . filter (liftE isDefEdge) . labEdgesDG

{-| 
   
Module      :  $Header$
Copyright   :  (c) Jorina F. Gerken, Till Mossakowski, Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  jfgerken@tzi.de
Stability   :  provisional
Portability :  non-portable(Logic)

global proofs in development graphs.
   Follows Sect. IV:4.4 of the CASL Reference Manual.
-}

{-
todo for Jorina:

   - bei GlobDecomp hinzuf�gen:
     zus�tzlich alle Pfade K<--theta-- M --sigma-->N in den aktuellen 
     Knoten N, die mit einem HidingDef anfangen, und danach nur GlobalDef
     theta ist der Signaturmorphismus des HidingDef's (geht "falsch rum")
     sigma ist die Komposition der Signaturmorphismen auf dem restl. Pfad
     f�r jeden solchen Pfad: einen HidingThm theta einf�gen. sigma ist
     der normale Morphismus (wie bei jedem anderen Link)
     siehe auch Seite 302 des CASL Reference Manual
-}

module Proofs.Global (globSubsume, globDecomp) where

import Data.List(nub)
import Logic.Grothendieck
import Static.DevGraph
import Static.DGToSpec
import Data.Graph.Inductive.Graph
import qualified Common.Lib.Map as Map
import Proofs.EdgeUtils
import Proofs.StatusUtils

-- ---------------------
-- global decomposition
-- ---------------------

{- apply rule GlobDecomp to all global theorem links in the current DG 
   current DG = DGm
   add to proof status the pair ([GlobDecomp e1,...,GlobDecomp en],DGm+1)
   where e1...en are the global theorem links in DGm
   DGm+1 results from DGm by application of GlobDecomp e1,...,GlobDecomp en -}


{- applies global decomposition to all unproven global theorem edges
   if possible -}
globDecomp :: ProofStatus -> IO ProofStatus
globDecomp proofStatus@(libname,libEnv,_) = do
  let dgraph = lookupDGraph libname proofStatus
      globalThmEdges = filter isUnprovenGlobalThm (labEdges dgraph)
      (newDGraph, newHistoryElem) = globDecompAux dgraph globalThmEdges ([],[])
--        (finalDGraph, finalHistoryElem) 
--            = removeSuperfluousInsertions newDGraph newHistoryElem
      newProofStatus = mkResultProofStatus proofStatus newDGraph newHistoryElem --finalDGraph finalHistoryElem
  return newProofStatus


{- removes all superfluous insertions from the list of changes as well as
   from the development graph  (i.e. insertions of edges that are
   equivalent to edges or paths resulting from the other insertions) -}
removeSuperfluousInsertions :: DGraph -> ([DGRule],[DGChange])
                                 -> (DGraph,([DGRule],[DGChange]))
removeSuperfluousInsertions dgraph (rules,changes)
  = (newDGraph,(rules,newChanges))

  where
    localThms = [edge | (InsertEdge edge) 
                        <- filter isLocalThmInsertion changes]
    (newDGraph, localThmsToInsert)
        = removeSuperfluousEdges dgraph localThms
    newChanges = (filter (not.isLocalThmInsertion) changes)
                     ++ [InsertEdge edge | edge <- localThmsToInsert]



{- auxiliary function for globDecomp (above)
   actual implementation -}
globDecompAux :: DGraph -> [LEdge DGLinkLab] -> ([DGRule],[DGChange])
              -> (DGraph,([DGRule],[DGChange]))
globDecompAux dgraph [] historyElem = (dgraph, historyElem)
globDecompAux dgraph (edge:list) historyElem =
  globDecompAux newDGraph list newHistoryElem

  where
    (newDGraph, newChanges) = globDecompForOneEdge dgraph edge
    newHistoryElem = (((GlobDecomp edge):(fst historyElem)),
                        (newChanges++(snd historyElem)))


-- applies global decomposition to a single edge
globDecompForOneEdge :: DGraph -> LEdge DGLinkLab -> (DGraph,[DGChange])
globDecompForOneEdge dgraph edge =
  globDecompForOneEdgeAux dgraph edge [] paths
  
  where
    source = getSourceNode edge
    defEdgesToSource = [e | e <- (labEdges dgraph), isDefEdge e && (getTargetNode e) == source]
    paths = [e:edge:[]|e <- defEdgesToSource]++[edge:[]]
    --getAllLocOrHideGlobDefPathsTo dgraph (getSourceNode edge) []
--    paths = [(node, path++(edge:[]))| (node,path) <- pathsToSource]

{- auxiliary funktion for globDecompForOneEdge (above)
   actual implementation -}
globDecompForOneEdgeAux :: DGraph -> LEdge DGLinkLab -> [DGChange] ->
                           [[LEdge DGLinkLab]] -> (DGraph,[DGChange])
{- if the list of paths is empty from the beginning, nothing is done
   otherwise the unprovenThm edge is replaced by a proven one -}
globDecompForOneEdgeAux dgraph edge@(source,target,edgeLab) changes [] = 
--  if null changes then (dgraph, changes)
  -- else
     if isDuplicate provenEdge dgraph changes
            then (delLEdge edge dgraph,
            ((DeleteEdge edge):changes))
      else ((insEdge provenEdge (delLEdge edge dgraph)),
            ((DeleteEdge edge):((InsertEdge provenEdge):changes)))

  where
    (GlobalThm _ conservativity conservStatus) = (dgl_type edgeLab)
    proofBasis = getInsertedEdges changes
    provenEdge = (source,
                  target,
                  DGLink {dgl_morphism = dgl_morphism edgeLab,
                          dgl_type = 
                            (GlobalThm (Proven (GlobDecomp edge) proofBasis)
                             conservativity conservStatus),
                          dgl_origin = DGProof}
                  )
-- for each path an unproven localThm edge is inserted
globDecompForOneEdgeAux dgraph edge@(_,target,_) changes
 (path:list) =
  if isDuplicate newEdge dgraph changes-- list
    then globDecompForOneEdgeAux dgraph edge changes list
   else globDecompForOneEdgeAux newGraph edge newChanges list

  where
    isHiding = not (null path) && isHidingDef (head path)
    morphismPath = if isHiding then tail path else path
    morphism = case calculateMorphismOfPath morphismPath of
                 Just morph -> morph
                 Nothing ->
                   error "globDecomp: could not determine morphism of new edge"
    newEdge = if isHiding then hidingEdge
               else if isGlobalDef (head path) then globalEdge else localEdge
    node = getSourceNode (head path)
    hidingEdge = 
       (node,
        target,
        DGLink {dgl_morphism = morphism,
                dgl_type = (HidingThm (dgl_morphism (getLabelOfEdge (head path))) LeftOpen),
                dgl_origin = DGProof})
    globalEdge = (node,
                  target,
                  DGLink {dgl_morphism = morphism,
                          dgl_type = (GlobalThm LeftOpen
                                      None LeftOpen),
                          dgl_origin = DGProof}
                 )
    localEdge = (node,
                 target,
                 DGLink {dgl_morphism = morphism,
                         dgl_type = (LocalThm LeftOpen
                                     None LeftOpen),
                         dgl_origin = DGProof}
               )
    newGraph = insEdge newEdge dgraph
    newChanges = ((InsertEdge newEdge):changes)

-- -------------------
-- global subsumption
-- -------------------

-- applies global subsumption to all unproven global theorem edges if possible
globSubsume ::  ProofStatus -> IO ProofStatus
globSubsume proofStatus@(ln,libEnv,_) = do
  let dgraph = lookupDGraph ln proofStatus
      globalThmEdges = filter isUnprovenGlobalThm (labEdges dgraph)
    -- the 'nub' is just a workaround, because some of the edges in the graph
    -- do not differ from each other in this representation - which causes
    -- problems on deletion
      result = globSubsumeAux libEnv dgraph ([],[]) (nub globalThmEdges)
      nextDGraph = fst result
      nextHistoryElem = snd result
      newProofStatus 
          = mkResultProofStatus proofStatus nextDGraph nextHistoryElem
  return newProofStatus


{- auxiliary function for globSubsume (above)
   the actual implementation -}
globSubsumeAux :: LibEnv ->  DGraph -> ([DGRule],[DGChange]) ->
                  [LEdge DGLinkLab] -> (DGraph,([DGRule],[DGChange]))
globSubsumeAux _ dgraph historyElement [] = (dgraph, historyElement)
globSubsumeAux libEnv dgraph (rules,changes) ((ledge@(src,tgt,edgeLab)):list) =
  if not (null proofBasis) || isIdentityEdge ledge libEnv dgraph
   then
     if isDuplicate newEdge dgraph changes then
        globSubsumeAux libEnv (delLEdge ledge dgraph) 
          (newRules,(DeleteEdge ledge):changes) list
      else
        globSubsumeAux libEnv (insEdge newEdge (delLEdge ledge dgraph))
          (newRules,(DeleteEdge ledge):((InsertEdge newEdge):changes)) list
   else 
     globSubsumeAux libEnv dgraph (rules,changes) list

  where
    morphism = dgl_morphism edgeLab
    allPaths = getAllGlobPathsOfMorphismBetween dgraph morphism src tgt
    filteredPaths = [path| path <- allPaths, notElem ledge path]
    proofBasis = selectProofBasis ledge filteredPaths
    (GlobalThm _ conservativity conservStatus) = dgl_type edgeLab
    newEdge = (src,
               tgt,
               DGLink {dgl_morphism = morphism,
                       dgl_type = (GlobalThm (Proven (GlobSubsumption ledge)
                                              proofBasis)
                                   conservativity conservStatus),
                       dgl_origin = DGProof}
               )
    newRules = (GlobSubsumption ledge):rules

-- ---------------------------------------------------------------------------
-- methods for the extension of globDecomp (avoid insertion ofredundant edges)
-- ---------------------------------------------------------------------------

{- returns all paths consisting of local theorem links whose src and tgt nodes
   are contained in the given list of nodes -}
localThmPathsBetweenNodes ::  DGraph -> [Node] -> [[LEdge DGLinkLab]]
localThmPathsBetweenNodes _ [] = []
localThmPathsBetweenNodes dgraph nodes@(_:_) =
  localThmPathsBetweenNodesAux dgraph nodes nodes

{- auxiliary method for localThmPathsBetweenNodes -}
localThmPathsBetweenNodesAux :: DGraph -> [Node] -> [Node] -> [[LEdge DGLinkLab]]
localThmPathsBetweenNodesAux _ [] _ = []
localThmPathsBetweenNodesAux dgraph (node:srcNodes) tgtNodes =
  (concat (map (getAllPathsOfTypeBetween dgraph isUnprovenLocalThm node) tgtNodes))
  ++ (localThmPathsBetweenNodesAux dgraph srcNodes tgtNodes)

{- combines each of the given paths with matching edges from the given list
   (i.e. every edge that has as its source node the tgt node of the path)-}
combinePathsWithEdges :: [[LEdge DGLinkLab]] -> [LEdge DGLinkLab]
                     -> [[LEdge DGLinkLab]]
combinePathsWithEdges paths edges =
  concat (map (combinePathsWithEdge paths) edges)

{- combines the given path with each matching edge from the given list
   (i.e. every edge that has as its source node the tgt node of the path)-}
combinePathsWithEdge :: [[LEdge DGLinkLab]] -> LEdge DGLinkLab
                     -> [[LEdge DGLinkLab]]
combinePathsWithEdge [] _ = []
combinePathsWithEdge (path:paths) edge@(src,_,_) =
  case path of
    [] -> combinePathsWithEdge paths edge
    (_:_) -> if (getTargetNode (last path)) == src 
              then (path++[edge]):(combinePathsWithEdge paths edge)
                else combinePathsWithEdge paths edge

{- todo: choose a better name for this method...
   returns for each of the given paths a pair consisting of the last edge
   contained in the path and - as a triple - the src, tgt and morphism of the
   complete path
   if there is an empty path in the given list or the morphsim cannot be
   calculated, it is simply ignored -}
calculateResultingEdges :: [[LEdge DGLinkLab]] -> [(LEdge DGLinkLab,(Node,Node,GMorphism))]
calculateResultingEdges [] = []
calculateResultingEdges (path:paths) =
  case path of
    [] -> calculateResultingEdges paths
    (_:_) ->
       case calculateMorphismOfPath path of
         Nothing -> calculateResultingEdges paths
         Just morphism -> (last path, (src,tgt,morphism)):(calculateResultingEdges paths)

  where src = getSourceNode (head path)
        tgt = getTargetNode (last path)

{- removes from the given list every edge for which there is already an
   equivalent edge or path (i.e. an edge or path with the same src, tgt and
   morphsim) -}
removeSuperfluousEdges :: DGraph -> [LEdge DGLinkLab]
                       -> (DGraph,[LEdge DGLinkLab])
removeSuperfluousEdges dgraph [] = (dgraph,[])
removeSuperfluousEdges dgraph edges
  = removeSuperfluousEdgesAux dgraph edges 
        (calculateResultingEdges combinedPaths) []

  where
    localThmPaths
        = localThmPathsBetweenNodes dgraph (map (getSourceNode) edges)
    combinedPaths = combinePathsWithEdges localThmPaths edges

{- auxiliary method for removeSuperfluousEdges -}
removeSuperfluousEdgesAux :: DGraph -> [LEdge DGLinkLab] 
                          -> [(LEdge DGLinkLab,(Node,Node,GMorphism))] 
                          -> [LEdge DGLinkLab] -> (DGraph,[LEdge DGLinkLab])
removeSuperfluousEdgesAux dgraph [] _ edgesToInsert= (dgraph,edgesToInsert)
removeSuperfluousEdgesAux dgraph ((edge@(src,tgt,edgeLab)):list) 
                          resultingEdges edgesToInsert =
  if not (null equivalentEdges)
     then removeSuperfluousEdgesAux
          newDGraph list newResultingEdges edgesToInsert
      else removeSuperfluousEdgesAux
           dgraph list resultingEdges (edge:edgesToInsert)

  where 
    equivalentEdges 
        = [e | e <- resultingEdges,(snd e) == (src,tgt,dgl_morphism edgeLab)]
    newResultingEdges = [e | e <- resultingEdges,(fst e) /= edge]
    newDGraph = delLEdge edge dgraph

{- returns true, if the given change is an insertion of an local theorem edge,
   false otherwise -}
isLocalThmInsertion :: DGChange -> Bool
isLocalThmInsertion change
  = case change of
      InsertEdge edge -> isLocalThm edge
      _ -> False

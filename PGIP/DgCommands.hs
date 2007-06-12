{- |
Module      :$Header$
Description : CMDL interface development graph commands
Copyright   : uni-bremen and DFKI
Licence     : similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  : r.pascanu@iu-bremen.de
Stability   : provisional
Portability : portable

PGIP.DgCommands contains all development graph commands 
that can be called from the CMDL interface
-} 

module PGIP.DgCommands where

import PGIP.CMDLState
import PGIP.CMDLUtils
import PGIP.CMDLShell

import Driver.Options
import Proofs.Automatic
import Proofs.Composition
import Proofs.Global
import Proofs.HideTheoremShift
import Proofs.Local
import Proofs.TheoremHideShift 
import Static.DGToSpec
import Syntax.AS_Library
import Static.DevGraph


import Common.Result

import Data.Graph.Inductive.Graph
import Static.AnalysisLibrary

import System.Console.Shell.ShellMonad


-- | General function for implementing dg all style commands
commandDgAll :: ( LIB_NAME->LibEnv->LibEnv) -> CMDLState
                      -> IO CMDLState
commandDgAll fn state
 = case devGraphState state of
    Nothing -> return state {
                      -- just an error message and leave
                      -- the internal state intact so that
                      -- the interface can recover
                      errorMsg = "No library loaded"
                      }
    Just dgState ->
     do 
      let nwLibEnv = fn (ln dgState) (libEnv dgState)
      return state {
              devGraphState = Just dgState {
                                    libEnv = nwLibEnv,
                                    -- are nodes left alone!?
                                    allEdges = [],
                                    allEdgesUpToDate = False},
              -- delete any selection if a dg command is used
              proveState = Nothing
              }


-- | Generic function for a dg command, all other dg 
-- commands are derived from this command by simply
-- specifing the function 
commandDg :: (LIB_NAME -> [LEdge DGLinkLab]->LibEnv->
              LibEnv) -> String -> CMDLState
                      -> IO CMDLState
commandDg fn input state
 = case devGraphState state of
    Nothing -> return state {
                      -- leave the internal state intact so
                      -- that the interface can recover
                      errorMsg = "No library loaded"
                      }
    Just dgState ->
     case decomposeIntoGoals input of
       (_,[],[]) -> return
                    state {
                    -- leave the internal state intact so 
                    -- that the interface can recover
                    errorMsg = "No edges in input string"
                    }
       (_,edg,nbEdg) ->
        do
        let lsNodes   = getAllNodes dgState
            lsEdges   = getAllEdges dgState
            -- compute the list of edges from the input
            listEdges = obtainEdgeList edg nbEdg lsNodes
                              lsEdges
            nwLibEnv = fn (ln dgState) listEdges 
                            (libEnv dgState)
        return state {
                  devGraphState = Just
                                  dgState {
                                    libEnv = nwLibEnv,
                                    -- are nodes left alone!?
                                    allNodes = lsNodes,
                                    allNodesUpToDate = True,
                                    allEdges = [],
                                    allEdgesUpToDate = False
                                    },
                  -- delete any selection if a dg command is
                  -- used
                  proveState = Nothing
                  }


-- | The function 'cUse' implements the Use commands, i.e. 
-- given a path it tries to load the library  at that path
cUse::String ->CMDLState -> IO CMDLState
cUse input state
 = do
   let opts = defaultHetcatsOpts
       file = input
   tmp <- case devGraphState state of 
           Nothing -> anaLib opts file
           Just dgState -> 
                   anaLibExt opts file $ libEnv dgState
   case tmp of 
    Nothing -> return state {
                 -- leave internal state intact so that 
                 -- the interface can recover
                 errorMsg = ("Unable to load library "++input)
                    }
    Just (nwLn, nwLibEnv) ->
                 return state {
                  devGraphState = Just  
                                   CMDLDevGraphState {
                                     ln = nwLn,
                                     libEnv = nwLibEnv,
                                     allNodes = [],
                                     allNodesUpToDate = False,
                                     allEdges = [],
                                     allEdgesUpToDate = False
                                     },
                  prompter = (file ++ "> "),
                  -- delete any selection if a dg command is 
                  -- used
                  proveState = Nothing
                  }

-- The only command that requires a list of nodes instead
-- of edges.
cDgThmHideShift :: String -> CMDLState -> IO CMDLState
cDgThmHideShift input state
 = case devGraphState state of
    Nothing -> return state {
                       -- leave internal state intact so 
                       -- that the interface can recover
                       errorMsg = "No library loaded"
                       }
    Just dgState ->
      case decomposeIntoGoals input of
       ([],_,_) -> return
                    state {
                     -- leave internal state intact so 
                     -- that the interface can recover
                     errorMsg = "No nodes in input string" 
                     }
       (nds,_,_) ->
         do
          let lsNodes = getAllNodes dgState
              listNodes = obtainNodeList nds lsNodes
              nwLibEnv = theoremHideShiftFromList (ln dgState)
                            listNodes (libEnv dgState)
          return state {
                   devGraphState = Just
                                    dgState {
                                     libEnv = nwLibEnv,
                                     -- are nodes left alone!?
                                     allNodes = lsNodes,
                                     allNodesUpToDate = True,
                                     -- are edges left alone!?
                                     allEdges = [],
                                     allEdgesUpToDate = False
                                     },
                   -- delte any selection if a dg command is
                   -- used
                   proveState = Nothing
                   }


shellDgThmHideShift :: String -> Sh CMDLState ()
shellDgThmHideShift 
 = shellComWith cDgThmHideShift

shellDgUse :: String -> Sh CMDLState ()
shellDgUse
 = shellComWith cUse

shellDgAuto :: String -> Sh CMDLState ()
shellDgAuto 
 = shellComWith $ commandDg automaticFromList

shellDgGlobSubsume:: String -> Sh CMDLState ()
shellDgGlobSubsume 
 = shellComWith $ commandDg globSubsumeFromList 

shellDgGlobDecomp:: String -> Sh CMDLState ()
shellDgGlobDecomp 
 = shellComWith $ commandDg globDecompFromList 

shellDgLocInfer :: String -> Sh CMDLState ()
shellDgLocInfer 
 = shellComWith $ commandDg localInferenceFromList

shellDgLocDecomp :: String -> Sh CMDLState ()
shellDgLocDecomp 
 = shellComWith $ commandDg locDecompFromList

shellDgComp :: String -> Sh CMDLState () 
shellDgComp 
 = shellComWith $ commandDg compositionFromList

shellDgCompNew :: String-> Sh CMDLState ()
shellDgCompNew
 = shellComWith $ commandDg compositionCreatingEdgesFromList

shellDgHideThm :: String-> Sh CMDLState ()
shellDgHideThm 
 = shellComWith $ commandDg automaticHideTheoremShiftFromList

shellDgAllAuto::  Sh CMDLState ()
shellDgAllAuto 
 = shellComWithout $ commandDgAll automatic
                         
shellDgAllGlobSubsume :: Sh CMDLState ()
shellDgAllGlobSubsume 
 = shellComWithout $ commandDgAll globSubsume 

shellDgAllGlobDecomp :: Sh CMDLState ()
shellDgAllGlobDecomp 
 = shellComWithout $ commandDgAll globDecomp 

shellDgAllLocInfer :: Sh CMDLState ()
shellDgAllLocInfer 
 = shellComWithout $ commandDgAll localInference

shellDgAllLocDecomp :: Sh CMDLState ()
shellDgAllLocDecomp 
 = shellComWithout $ commandDgAll locDecomp

shellDgAllComp :: Sh CMDLState ()
shellDgAllComp 
 = shellComWithout $ commandDgAll composition

shellDgAllCompNew :: Sh CMDLState ()
shellDgAllCompNew 
 = shellComWithout $ commandDgAll compositionCreatingEdges

shellDgAllHideThm :: Sh CMDLState ()
shellDgAllHideThm 
 = shellComWithout $ commandDgAll automaticHideTheoremShift

shellDgAllThmHide :: Sh CMDLState ()
shellDgAllThmHide 
 = shellComWithout $ commandDgAll theoremHideShift


-- selection commands

-- | function swithces interface in proving mode and also 
-- selects a list of nodes to be used inside this mode
cDgSelect :: String -> CMDLState -> IO CMDLState
cDgSelect input state 
 = case devGraphState state of
    Nothing -> return state {
                       -- leave internal state intact so
                       -- that the interface can recover
                       errorMsg = "No library loaded"
                       }
    Just dgState ->
      case decomposeIntoGoals input of
       ([],_,_) -> return 
                    state {
                     -- leave internal state intact so 
                     -- that the interface can recover
                     errorMsg = "No noes in input string"
                     }
       (nds,_,_) ->
         do
              -- list of all nodes
          let lsNodes = getAllNodes dgState
              -- list of input nodes
              listNodes = obtainNodeList nds lsNodes
              -- computes the theory of a given node 
              -- (i.e. solves DGRef cases and so on,
              -- see CASL Reference Manual, p.294, Def 4.9)
              -- computeTheory is defined in Static.DGToSpec
              gth n = computeTheory (libEnv dgState)     
                                    (ln dgState)
                                    n
              -- if compute theory was successful give the
              -- result as one element list, otherwise an
              -- empty list
              fn x = case gth x of
                      Result _ (Just th) ->
                        [CMDLProveElement {
                          nodeNumber = x,
                          theory = th,
                          theorems = [],
                          axioms = []
                          }
                        ]
                      _ -> []
              -- elems is the list of all results (i.e. 
              -- concat of all one element lists)
              elems = concatMap 
                       (\x -> case x of
                               (n,_) -> fn n 
                               ) listNodes
          return state {
                   -- keep the list of nodes as up to date
                   devGraphState = Just 
                                    dgState {
                                      allNodes = lsNodes,
                                      allNodesUpToDate = True
                                      },
                   -- add the prove state to the status
                   -- containing all information selected
                   -- in the input
                   proveState = Just
                                 CMDLProveState {
                                   elements = elems,
                                   uComorphisms = [],
                                   prover = Nothing,
                                   script = ""
                                   }
                   }



shellDgSelect :: String -> Sh CMDLState ()
shellDgSelect  
 = shellComWith cDgSelect



-- | Function switches the interface in proving mode by
-- selecting all nodes
cDgSelectAll :: CMDLState -> IO CMDLState
cDgSelectAll state
 = case devGraphState state of
    Nothing -> return state {
                       -- leave internal state intact so 
                       -- that the interface can recover
                       errorMsg = "No library loaded"
                       }
    Just dgState ->
     do
          -- list of all nodes
      let lsNodes = getAllNodes dgState
          -- compute the theory of a given node (i.e. solves
          -- DGRef cases and so on, see CASL Reference 
          -- Manual, p.294,Def 4.9), computeTheory is 
          -- defined in Static.DGToSpec
          gth n = computeTheory (libEnv dgState) 
                               (ln dgState)
                               n
          fn x = case gth x of
                  Result _ (Just th) ->
                   [CMDLProveElement {
                      nodeNumber = x,
                      theory = th,
                      theorems = [],
                      axioms = []
                      }
                   ]
                  _ -> []
          -- elems is the list of all results (i.e. concat
          -- of all one element lists)
          elems = concatMap
                   (\x -> case x of 
                           (n,_) -> fn n
                           ) lsNodes
      return state {
              -- keep the list of nodes as up to date
              devGraphState = Just
                               dgState {
                                 allNodes = lsNodes,
                                 allNodesUpToDate = True
                                 },
              -- add the prove state to the status containing
              -- all information selected in the input
              proveState = Just
                            CMDLProveState {
                              elements = elems,
                              uComorphisms = [],
                              prover = Nothing,
                              script = ""
                              }
              }


shellDgSelectAll :: Sh CMDLState ()
shellDgSelectAll
 = shellComWithout cDgSelectAll


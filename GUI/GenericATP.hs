{- |
Module      :  $Header$
Description :  Generic Prover GUI.
Copyright   :  (c) Klaus Luettich, Rainer Grabbe, Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  rainer25@informatik.uni-bremen.de
Stability   :  provisional
Portability :  needs POSIX

Generic GUI for automatic theorem provers. Based upon former SPASS Prover GUI.

-}

module GUI.GenericATP (genericATPgui,guiDefaultTimeLimit) where

import Logic.Prover

import qualified Common.AS_Annotation as AS_Anno
import qualified Data.Map as Map
import Common.Utils (getEnvSave)
import Common.Result

import Data.List
import Data.Maybe (isJust)
import qualified Control.Exception as Exception
import qualified Control.Concurrent as Conc

import GHC.Read

import HTk hiding (value)
import qualified HTk (value)
import SpinButton
import Messages
import TextDisplay
import Separator
import XSelection
import Space
import ScrollBar

import GUI.HTkUtils
import GUI.GenericATPState
import GUI.PrintUtils

import Proofs.BatchProcessing

-- debugging
import Debug.Trace

{- |
  Utility function to set the time limit of a Config.
  For values <= 0 a default value is used.
-}
setTimeLimit :: Int -> GenericConfig proof_tree -> GenericConfig proof_tree
setTimeLimit n c = if n > 0 then c{timeLimit = Just n}
                   else c{timeLimit = Nothing}

{- |
  Utility function to set the extra options of a Config.
-}
setExtraOpts :: [String] -> GenericConfig proof_tree -> GenericConfig proof_tree
setExtraOpts opts c = c{extraOpts = opts}

-- ** Constants

{- |
  Default time limit for the GUI mode prover in seconds.
-}
guiDefaultTimeLimit :: Int
guiDefaultTimeLimit = 10


-- ** Defining the view

{- |
  Colors used by the GUI to indicate the status of a goal.
-}
data ProofStatusColour
  -- | Proved
  = Green
  -- | Proved, but theory is inconsistent
  | Brown
  -- | Disproved
  | Red
  -- | Open
  | Black
  -- | Running
  | Blue
   deriving (Bounded,Enum,Show)

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Proved proof
  status.
-}
statusProved :: (ProofStatusColour, String)
statusProved = (Green, "Proved")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Proved
  (but inconsistent) proof status.
-}
statusProvedButInconsistent :: (ProofStatusColour, String)
statusProvedButInconsistent = (Brown, "Proved (Theory inconsistent!)")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Disproved
  proof status.
-}
statusDisproved :: (ProofStatusColour, String)
statusDisproved = (Red, "Disproved")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing an Open proof
  status.
-}
statusOpen :: (ProofStatusColour, String)
statusOpen = (Black, "Open")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing an Open proof
  status in case the time limit has been exceeded.
-}
statusOpenTExceeded :: (ProofStatusColour, String)
statusOpenTExceeded = (Black, "Open (Time is up!)")

{- |
  Generates a ('ProofStatusColour', 'String') tuple representing a Running proof
  status.
-}
statusRunning :: (ProofStatusColour, String)
statusRunning = (Blue, "Running")

{- |
  Converts a 'Proof_status' into a ('ProofStatusColour', 'String') tuple to be
  displayed by the GUI.
-}
toGuiStatus :: GenericConfig proof_tree -- ^ current prover configuration
            -> (Proof_status a) -- ^ status to convert
            -> (ProofStatusColour, String)
toGuiStatus cf st = case goalStatus st of
  Proved mc -> maybe (statusProved)
                     ( \ c -> if c
                              then statusProved
                              else statusProvedButInconsistent)
                     mc
  Disproved -> statusDisproved
  _         -> if timeLimitExceeded cf
               then statusOpenTExceeded
               else statusOpen

{- | stores widgets of an options frame and the frame itself -}
data OpFrame = OpFrame { of_Frame :: Frame
                       , of_timeSpinner :: SpinButton
                       , of_timeEntry :: Entry Int
                       , of_optionsEntry :: Entry String
                       }

{- |
  Generates a list of 'GUI.HTkUtils.LBGoalView' representations of all goals
  from a 'GenericATPState.GenericState'.
-}
goalsView :: GenericState sign sentence proof_tree pst -- ^ current global
                                                       -- prover state
          -> [LBGoalView] -- ^ resulting ['LBGoalView'] list
goalsView s = map (\ g ->
                      let cfg = Map.lookup g (configsMap s)
                          statind = maybe LBIndicatorOpen
                                     (indicatorFromProof_status . proof_status)
                                     cfg
                       in
                         LBGoalView {statIndicator = statind,
                                     goalDescription = g})
                  (map AS_Anno.senAttr (goalsList s))

-- * GUI Implementation

-- ** Utility Functions

{- |
  Retrieves the value of the time limit 'Entry'. Ignores invalid input.
-}
getValueSafe :: Int -- ^ default time limt
             -> Entry Int -- ^ time limit 'Entry'
             -> IO Int -- ^ user-requested time limit or default in case of a
                       -- parse error
getValueSafe defaultTimeLimit timeEntry =
    Exception.catchJust Exception.userErrors ((getValue timeEntry) :: IO Int)
                  (\ s -> trace ("Warning: Error "++show s++" was ignored")
                                (return defaultTimeLimit))

{- |
  reads passed ENV-variable and if it exists and has an Int-value this value is
  returned otherwise the value of 'batchTimeLimit' is returned.
-}

getBatchTimeLimit :: String -- ^ ENV-variable containing batch time limit
                  -> IO Int
getBatchTimeLimit env =
    getEnvSave batchTimeLimit env readEither

{- |
  Text displayed by the batch mode window.
-}
batchInfoText :: Int -- ^ batch time limt
              -> Int -- ^ total number of goals
              -> Int -- ^ number of that have been processed
              -> String
batchInfoText tl gTotal gDone =
  let totalSecs = (gTotal - gDone) * tl
      (remMins,secs) = divMod totalSecs 60
      (hours,mins) = divMod remMins 60
  in
  "Batch mode running.\n"++
  show gDone ++ "/" ++ show gTotal ++ " goals processed.\n" ++
  "At most "++show hours++"h "++show mins++"m "++show secs++"s remaining."


-- ** Callbacks

{- |
   Updates the display of the status of the current goal.
-}
updateDisplay :: GenericState sign sentence proof_tree pst
                 -- ^ current global prover state
              -> Bool -- ^ set to 'True' if you want the 'ListBox' to be
                      -- updated
              -> ListBox String -- ^ 'ListBox' displaying the status of all
                                -- goals (see 'goalsView')
{-
              -> Scrollbar -- ^ 'ScrollBar' containing the current scrollbar
                           -- status of upper 'ListBox'.
-}
              -> Label -- ^ 'Label' displaying the status of the currently
                       -- selected goal (see 'toGuiStatus')
              -> Entry Int -- ^ 'Entry' containing the time limit of the current
                           -- goal
              -> Entry String -- ^ 'Entry' containing the extra options
              -> ListBox String -- ^ 'ListBox' displaying all axioms used to
                                -- prove a goal (if any)
              -> IO ()
updateDisplay st updateLb goalsLb statusLabel timeEntry optionsEntry axiomsLb =
{- the code in comments only works with an updated uni version that
   will be installed when switching to ghc-6.6.1 -}
  do
    when updateLb (do
           (offScreen,_) <- view Vertical goalsLb
           populateGoalsListBox goalsLb (goalsView st)
           moveto Vertical goalsLb offScreen
          )
    maybe (return ())
          (\ go ->
               let mprfst = Map.lookup go (configsMap st)
                   cf = Map.findWithDefault
                        (error "GUI.GenericATP.updateDisplay")
                        go (configsMap st)
                   t' = maybe guiDefaultTimeLimit id (timeLimit cf)
                   opts' = unwords (extraOpts cf)
                   (color, label) = maybe statusOpen
                                    ((toGuiStatus cf) . proof_status)
                                    mprfst
                   usedAxs = maybe [] (usedAxioms . proof_status) mprfst

               in do
                statusLabel # text label
                statusLabel # foreground (show color)
                timeEntry # HTk.value t'
                optionsEntry # HTk.value opts'
                axiomsLb # HTk.value (usedAxs::[String])
                return ())
          (currentGoal st)

newOptionsFrame :: Container par =>
                par -- ^ the parent container
             -> (Entry Int -> Spin -> IO a)
             -- ^ Function called by pressing one spin button
             -> Bool -- ^ extra options input line
             -> IO OpFrame
newOptionsFrame con updateFn isExtraOps = do
  right <- newFrame con []

  -- contents of newOptionsFrame
  l1 <- newLabel right [text "Options:"]
  pack l1 [Anchor NorthWest]
  opFrame <- newFrame right []
  pack opFrame [Expand On, Fill X, Anchor North]

  spacer <- newLabel opFrame [text "   "]
  pack spacer [Side AtLeft]

  opFrame2 <- newVBox opFrame []
  pack opFrame2 [Expand On, Fill X, Anchor NorthWest]

  timeLimitFrame <- newFrame opFrame2 []
  pack timeLimitFrame [Expand On, Fill X, Anchor West]

  l2 <- newLabel timeLimitFrame [text "TimeLimit"]
  pack l2 [Side AtLeft]

  -- extra HBox for time limit display
  timeLimitLine <- newHBox timeLimitFrame []
  pack timeLimitLine [Expand On, Side AtRight, Anchor East]

  (timeEntry :: Entry Int) <- newEntry timeLimitLine [width 18,
                                              HTk.value guiDefaultTimeLimit]
  pack timeEntry []

  timeSpinner <- newSpinButton timeLimitLine (updateFn timeEntry) []
  pack timeSpinner []

  l3 <- newLabel opFrame2 [text "Extra Options:"]
  when isExtraOps $
       pack l3 [Anchor West]
  (optionsEntry :: Entry String) <- newEntry opFrame2 [width 37]
  when isExtraOps $
       pack optionsEntry [Fill X, PadX (cm 0.1)]

  return $ OpFrame { of_Frame = right
                   , of_timeSpinner = timeSpinner
                   , of_timeEntry = timeEntry
                   , of_optionsEntry = optionsEntry}

-- ** Main GUI

{- |
  Invokes the prover GUI. Users may start the batch prover run on all goals,
  or use a detailed GUI for proving each goal manually.
-}
genericATPgui :: (Ord proof_tree, Ord sentence, Show proof_tree, Show sentence)
              => ATPFunctions sign sentence proof_tree pst -- ^ prover specific
                                                           -- functions
              -> Bool -- ^ prover supports extra options
              -> String -- ^ prover name
              -> String -- ^ theory name
              -> Theory sign sentence proof_tree -- ^ theory consisting of a
                 -- signature and a list of Named sentence
              -> proof_tree -- ^ initial empty proof_tree
              -> IO([Proof_status proof_tree]) -- ^ proof status for each goal
genericATPgui atpFun isExtraOptions prName thName th pt = do
  -- create initial backing data structure
  let initState = initialGenericState prName
                                      (initialProverState atpFun)
                                      (atpTransSenName atpFun) th pt
  stateMVar <- Conc.newMVar initState
  batchTLimit <- getBatchTimeLimit $ batchTimeEnv atpFun

  -- main window
  main <- createToplevel [text $ thName ++ " - " ++ prName ++ " Prover"]
  pack main [Expand On, Fill Both]

  -- VBox for the whole window
  b <- newVBox main []
  pack b [Expand On, Fill Both]

  -- HBox for the upper part (goals on the left, options/results on the right)
  b2 <- newHBox b []
  pack b2 [Expand On, Fill Both]

  -- left frame (goals)
  left <- newFrame b2 []
  pack left [Expand On, Fill Both]

  b3 <- newVBox left []
  pack b3 [Expand On, Fill Both]

  l0 <- newLabel b3 [text "Goals:"]
  pack l0 [Anchor NorthWest]

  lbFrame <- newFrame b3 []
  pack lbFrame [Expand On, Fill Both]

  lb <- newListBox lbFrame [bg "white",exportSelection False,
                            selectMode Single, height 15] :: IO (ListBox String)
  pack lb [Expand On, Side AtLeft, Fill Both]
  sb <- newScrollBar lbFrame []
  pack sb [Expand On, Side AtRight, Fill Y, Anchor West]
  lb # scrollbar Vertical sb

  -- right frame (options/results)
  OpFrame { of_Frame = right
          , of_timeSpinner = timeSpinner
          , of_timeEntry = timeEntry
          , of_optionsEntry = optionsEntry}
      <- newOptionsFrame b2
                 (\ timeEntry sp -> synchronize main
                   (do
               st <- Conc.readMVar stateMVar
               maybe noGoalSelected
                     (\ goal ->
                      do
                      curEntTL <- getValueSafe guiDefaultTimeLimit timeEntry
                      s <- Conc.takeMVar stateMVar
                      let sEnt = s {configsMap =
                                        adjustOrSetConfig
                                             (setTimeLimit curEntTL)
                                             prName goal pt (configsMap s)}
                          cfg = getConfig prName goal pt (configsMap sEnt)
                          t = timeLimit cfg
                          t' = (case sp of
                                Up -> maybe (guiDefaultTimeLimit + 10)
                                            (+10)
                                            t
                                _ -> maybe (guiDefaultTimeLimit - 10)
                                            (\ t1 -> t1-10)
                                            t)
                          s' = sEnt {configsMap =
                                         adjustOrSetConfig
                                              (setTimeLimit t')
                                              prName goal pt (configsMap sEnt)}
                      Conc.putMVar stateMVar s'
                      timeEntry # HTk.value
                                    (maybe guiDefaultTimeLimit
                                           id
                                           (timeLimit $
                                              getConfig prName goal pt $
                                                configsMap s'))
                      done)
                     (currentGoal st)))
                 isExtraOptions
  pack right [Expand On, Fill Both, Anchor NorthWest]

  -- buttons for options
  buttonsHb1 <- newHBox right []
  pack buttonsHb1 [Anchor NorthEast]

  saveProbButton <- newButton buttonsHb1 [text $ "Save "
      ++ (removeFirstDot $ problemOutput $ fileExtensions atpFun)
      ++ " File"]
  pack saveProbButton [Side AtLeft]
  proveButton <- newButton buttonsHb1 [text "Prove"]
  pack proveButton [Side AtRight]

  -- result frame
  resultFrame <- newFrame right []
  pack resultFrame [Expand On, Fill Both]

  l4 <- newLabel resultFrame [text ("Results:"++replicate 70 ' ')]
  pack l4 [Anchor NorthWest]

  spacer <- newLabel resultFrame [text "   "]
  pack spacer [Side AtLeft]

  resultContentBox <- newHBox resultFrame []
  pack resultContentBox [Expand On, Anchor West, Fill Both]

  -- labels on the left side
  rc1 <- newVBox resultContentBox []
  pack rc1 [Expand Off, Anchor North]
  l5 <- newLabel rc1 [text "Status"]
  pack l5 [Anchor West]
  l6 <- newLabel rc1 [text "Used Axioms"]
  pack l6 [Anchor West]

  -- contents on the right side
  rc2 <- newVBox resultContentBox []
  pack rc2 [Expand On, Fill Both, Anchor North]

  statusLabel <- newLabel rc2 [text " -- "]
  pack statusLabel [Anchor West]
  axiomsFrame <- newFrame rc2 []
  pack axiomsFrame [Expand On, Anchor West, Fill Both]
  axiomsLb <- newListBox axiomsFrame [HTk.value $ ([]::[String]),
                                      bg "white",exportSelection False,
                                      selectMode Browse,
                                      height 6, width 19] :: IO (ListBox String)
  pack axiomsLb [Side AtLeft, Expand On, Fill Both]
  axiomsSb <- newScrollBar axiomsFrame []
  pack axiomsSb [Side AtRight, Fill Y, Anchor West]
  axiomsLb # scrollbar Vertical axiomsSb

  detailsButton <- newButton resultFrame [text "Show Details"]
  pack detailsButton [Anchor NorthEast]

  -- separator
  sp1 <- newSpace b (cm 0.15) []
  pack sp1 [Expand Off, Fill X, Side AtBottom]

  newHSeparator b

  sp2 <- newSpace b (cm 0.15) []
  pack sp2 [Expand Off, Fill X, Side AtBottom]

  -- batch mode frame
  batch <- newFrame b []
  pack batch [Expand Off, Fill X]

  batchTitle <- newLabel batch [text $ (prName)++" Batch Mode:"]
  pack batchTitle [Side AtTop]

  batchIFrame <- newFrame batch []
  pack batchIFrame [Expand On, Fill X]

  batchRight <- newVBox batchIFrame []
  pack batchRight [Expand On, Fill X, Side AtRight]

  batchBtnBox <- newHBox batchRight []
  pack batchBtnBox [Expand On, Fill X, Side AtRight]
  stopBatchButton <- newButton batchBtnBox [text "Stop"]
  pack stopBatchButton []
  runBatchButton <- newButton batchBtnBox [text "Run"]
  pack runBatchButton []

  batchSpacer <- newSpace batchRight (pp 150) [orient Horizontal]
  pack batchSpacer [Side AtRight]
  batchStatusLabel <- newLabel batchRight [text "\n\n"]
  pack batchStatusLabel []

  OpFrame { of_Frame = batchLeft
          , of_timeSpinner = batchTimeSpinner
          , of_timeEntry = batchTimeEntry
          , of_optionsEntry = batchOptionsEntry}
      <- newOptionsFrame batchIFrame
                 (\ tEntry sp -> synchronize main
                   (do
                    curEntTL <- getValueSafe batchTLimit tEntry
                    let t' = case sp of
                              Up -> curEntTL+10
                              _ -> max batchTLimit (curEntTL-10)
                    tEntry # HTk.value t'
                    done))
                 isExtraOptions

  pack batchLeft [Expand On, Fill X, Anchor NorthWest, Side AtLeft]

  batchGoal <- newHBox batch []
  pack batchGoal [Expand On, Fill X, Anchor West, Side AtBottom]
  batchCurrentGoalTitle <- newLabel batchGoal [text "Current goal:"]
  pack batchCurrentGoalTitle []
  batchCurrentGoalLabel <- newLabel batchGoal [text "--"]
  pack batchCurrentGoalLabel []


  saveProblem_batch <- createTkVariable False
  saveProblem_batch_checkBox <-
         newCheckButton batchLeft
                      [variable saveProblem_batch,
                       text $ "Save "
                   ++ (removeFirstDot $ problemOutput $ fileExtensions atpFun)]

  enableSaveCheckBox <- getEnvSave False "HETS_ENABLE_BATCH_SAVE" readEither
  when enableSaveCheckBox $
       pack saveProblem_batch_checkBox [Expand Off, Fill None, Side AtBottom]

  batchTimeEntry # HTk.value batchTLimit

  -- separator 2
  sp1_2 <- newSpace b (cm 0.15) []
  pack sp1_2 [Expand Off, Fill X, Side AtBottom]

  newHSeparator b

  sp2_2 <- newSpace b (cm 0.15) []
  pack sp2_2 [Expand Off, Fill X, Side AtBottom]

  -- global options frame
  globalOptsFr <- newFrame b []
  pack globalOptsFr [Expand Off, Fill Both]

  gOptsTitle <- newLabel globalOptsFr [text "Global Options:"]
  pack gOptsTitle [Side AtTop]

  inclProvedThsTK <- createTkVariable True
  inclProvedThsCheckButton <-
         newCheckButton globalOptsFr
                        [variable inclProvedThsTK,
                         text ("include preceeding proven therorems"++
                               " in next proof attempt")]
  pack inclProvedThsCheckButton [Side AtLeft]

  -- separator 3
  sp1_3 <- newSpace b (cm 0.15) []
  pack sp1_3 [Expand Off, Fill X, Side AtBottom]

  newHSeparator b

  sp2_3 <- newSpace b (cm 0.15) []
  pack sp2_3 [Expand Off, Fill X, Side AtBottom]

  -- bottom frame (help/save/exit buttons)
  bottom <- newHBox b []
  pack bottom [Expand Off, Fill Both]

  helpButton <- newButton bottom [text "Help"]
  pack helpButton [PadX (cm 0.3), IPadX (cm 0.1)]  -- wider "Help" button
  saveButton <- newButton bottom [text "Save Prover Configuration"]
  pack saveButton [PadX (cm 0.3)]
  exitButton <- newButton bottom [text "Exit Prover"]
  pack exitButton [PadX (cm 0.3)]

  populateGoalsListBox lb (goalsView initState)
  putWinOnTop main

  -- MVars for thread-safe communication
  mVar_batchId <- Conc.newEmptyMVar :: IO (Conc.MVar Conc.ThreadId)
  windowDestroyedMVar <- Conc.newEmptyMVar :: IO (Conc.MVar ())

  -- events
  (selectGoal, _) <- bindSimple lb (ButtonPress (Just 1))
  doProve <- clicked proveButton
  saveProb <- clicked saveProbButton
  showDetails <- clicked detailsButton

  runBatch <- clicked runBatchButton
  stopBatch <- clicked stopBatchButton

  help <- clicked helpButton
  saveConfiguration <- clicked saveButton
  exit <- clicked exitButton

  (closeWindow,_) <- bindSimple main Destroy

  let goalSpecificWids = [EnW timeEntry, EnW timeSpinner,EnW optionsEntry] ++
                         map EnW [proveButton,detailsButton,saveProbButton]
      wids = EnW lb : goalSpecificWids ++
             [EnW batchTimeEntry, EnW batchTimeSpinner,
              EnW saveProblem_batch_checkBox,
              EnW batchOptionsEntry,EnW inclProvedThsCheckButton] ++
             map EnW [helpButton,saveButton,exitButton,runBatchButton]

  disableWids goalSpecificWids
  disable stopBatchButton

  -- event handlers
  spawnEvent
    (forever
      ((selectGoal >>> do
          s <- Conc.takeMVar stateMVar
          let oldGoal = currentGoal s
          curEntTL <- (getValueSafe guiDefaultTimeLimit timeEntry) :: IO Int
          let s' = maybe s
                         (\ og -> s
                             {configsMap =
                                  adjustOrSetConfig (setTimeLimit curEntTL)
                                                    prName og pt
                                                    (configsMap s)})
                         oldGoal
          sel <- (getSelection lb) :: IO (Maybe [Int])
          let s'' = maybe s' (\ sg -> s' {currentGoal =
                                              Just $ AS_Anno.senAttr
                                               (goalsList s' !! head sg)})
                             sel
          Conc.putMVar stateMVar s''
          batchModeRunning <- isBatchModeRunning mVar_batchId
          when (isJust sel && not batchModeRunning)
               (enableWids goalSpecificWids)
          when (isJust sel) $ enableWids [EnW detailsButton,EnW saveProbButton]
          updateDisplay s'' False lb statusLabel timeEntry optionsEntry axiomsLb
          done)
      +> (saveProb >>> do
            rs <- Conc.readMVar stateMVar
            curEntTL <- (getValueSafe guiDefaultTimeLimit
                                      timeEntry) :: IO Int
            inclProvedThs <- readTkVariable inclProvedThsTK
            maybe (return ())
                  (\ goal -> do
                      let (nGoal,lp') =
                              prepareLP (proverState rs)
                                        rs goal inclProvedThs
                          s = rs {configsMap = adjustOrSetConfig
                                            (setTimeLimit curEntTL)
                                            prName goal pt
                                            (configsMap rs)}
                      extraOptions <- (getValue optionsEntry) :: IO String
                      let s' = s {configsMap = adjustOrSetConfig
                                            (setExtraOpts (words extraOptions))
                                            prName goal pt
                                            (configsMap s)}

                      prob <- (goalOutput atpFun) lp' nGoal $
                        (createProverOptions atpFun)
                          (getConfig prName goal pt $ configsMap s')
                      createTextSaveDisplay
                        (prName++" Problem for Goal "++goal)
                        (thName++'_':goal
                               ++(problemOutput $ fileExtensions atpFun))
                        (prob)
                  )
                  $ currentGoal rs
            done)
      +> (doProve >>> do
            rs <- Conc.readMVar stateMVar
            case currentGoal rs of
              Nothing -> noGoalSelected >> done
              Just goal -> do
                curEntTL <- (getValueSafe guiDefaultTimeLimit
                                          timeEntry) :: IO Int
                inclProvedThs <- readTkVariable inclProvedThsTK
                let s = rs {configsMap = adjustOrSetConfig
                                            (setTimeLimit curEntTL)
                                            prName goal pt
                                            (configsMap rs)}
                    (nGoal,lp') = prepareLP (proverState rs)
                                        rs goal inclProvedThs
                extraOptions <- (getValue optionsEntry) :: IO String
                let s' = s {configsMap = adjustOrSetConfig
                                            (setExtraOpts (words extraOptions))
                                            prName goal pt
                                            (configsMap s)}
                statusLabel # text (snd statusRunning)
                statusLabel # foreground (show $ fst statusRunning)
                disableWids wids
                (retval, cfg) <-
                    (runProver atpFun) lp'
                          (getConfig prName goal pt $ configsMap s') False
                          thName nGoal
                -- check if window was closed
                wDestroyed <- windowDestroyed windowDestroyedMVar
                if wDestroyed
                 then done
                 else do
                 case retval of
                   ATPError m -> errorMess m
                   _ -> return ()
                 let s'' = s'{
                     configsMap =
                        adjustOrSetConfig
                           (\ c -> c {timeLimitExceeded = isTimeLimitExceeded
                                                            retval,
                                      proof_status =
                                          ((proof_status cfg)
                                           {usedTime = timeUsed cfg}),
                                      resultOutput = resultOutput cfg,
                                      timeUsed     = timeUsed cfg})
                           prName goal pt (configsMap s')}
                 Conc.modifyMVar_ stateMVar (return . const s'')
                -- check again if window was closed
                 wDestroyed2 <- windowDestroyed windowDestroyedMVar
                 if wDestroyed2
                  then done
                  else do
                    enable lb
                    enable axiomsLb
                    updateDisplay s'' True lb statusLabel timeEntry
                                  optionsEntry axiomsLb
                    enableWids wids
                 done)
      +> (showDetails >>> do
            Conc.yield
            s <- Conc.readMVar stateMVar
            case currentGoal s of
              Nothing -> noGoalSelected >> done
              Just goal -> do
                let result = Map.lookup goal (configsMap s)
                    output = maybe ["This goal hasn't been run through "++
                                     "the prover yet."]
                                   resultOutput
                                   result
                    detailsText = concatMap ('\n':) output
                createTextSaveDisplay (prName ++ " Output for Goal "++goal)
                        (goal ++ (proverOutput $ fileExtensions atpFun))
                        (seq (length detailsText) detailsText)
                done)
      +> (runBatch >>> do
            s <- Conc.readMVar stateMVar
            -- get options for this batch run
            curEntTL <- (getValueSafe batchTLimit batchTimeEntry) :: IO Int
            let tLimit = if curEntTL > 0 then curEntTL else batchTLimit
            batchTimeEntry # HTk.value tLimit
            extOpts <- (getValue batchOptionsEntry) :: IO String
            let extOpts' = words extOpts
                openGoalsMap =  filterOpenGoals $ configsMap s
                numGoals = Map.size openGoalsMap
                firstGoalName = maybe "--" id $
                                find ((flip Map.member) openGoalsMap) $
                                map AS_Anno.senAttr (goalsList s)
            if numGoals > 0
             then do
              let afterEachProofAttempt =
                -- this function is called after the prover returns from a
                -- proof attempt (... -> IO Bool)
                   (\ gPSF nSen nextSen cfg@(retval,_) -> do
                     cont <- goalProcessed stateMVar tLimit extOpts'
                                           numGoals prName gPSF nSen cfg
                     mTId <- Conc.tryTakeMVar mVar_batchId
                     (flip (maybe (return False))) mTId
                        (\ tId -> do
                           stored <- Conc.tryPutMVar
                                                 mVar_batchId
                                                 tId
                           if not stored
                              then fail $ "GenericATP: Thread "++
                                          "run check failed"
                              else do
                            wDestroyed <- windowDestroyed windowDestroyedMVar
                            if wDestroyed
                              then return False
                              else do
                               batchStatusLabel #
                                  text (if cont
                                        then (batchInfoText tLimit
                                                      numGoals gPSF)
                                        else "Batch mode finished\n\n")
                               setCurrentGoalLabel batchCurrentGoalLabel
                                  (if cont
                                      then maybe "--" AS_Anno.senAttr nextSen
                                      else "--")
                               st <- Conc.readMVar stateMVar
                               updateDisplay st True lb statusLabel timeEntry
                                            optionsEntry axiomsLb
                               case retval of
                                ATPError m -> errorMess m
                                _ -> return ()
                               batchModeRunning <-
                                   isBatchModeRunning mVar_batchId
                               let cont' = cont && batchModeRunning
                               when (not cont)
                                   (do
                                    disable stopBatchButton
                                    enableWids wids
                                    enableWidsUponSelection lb goalSpecificWids
                                    cleanupThread mVar_batchId)
                               return cont'))
                    -- END of afterEachProofAttempt
              batchStatusLabel # text (batchInfoText tLimit numGoals 0)
              setCurrentGoalLabel batchCurrentGoalLabel firstGoalName
              disableWids wids
              enable stopBatchButton
              enableWidsUponSelection lb [EnW detailsButton,EnW saveProbButton]
              enable lb
              inclProvedThs <- readTkVariable inclProvedThsTK
              saveProblem_F <- readTkVariable saveProblem_batch
              batchProverId <- Conc.forkIO
                   (do genericProveBatch False tLimit extOpts' inclProvedThs
                                      saveProblem_F
                          afterEachProofAttempt
                          (atpInsertSentence atpFun) (runProver atpFun)
                          prName thName s Nothing
                       return ())
              stored <- Conc.tryPutMVar mVar_batchId batchProverId
              if stored
                 then done
                 else fail "GenericATP: MVar for batchProverId already taken!!"
             else {- numGoals < 1 -} do
              batchStatusLabel # text ("No further open goals\n\n")
              batchCurrentGoalLabel # text "--"
              done)
      +> (stopBatch >>> do
            cleanupThread mVar_batchId
            wDestroyed <- windowDestroyed windowDestroyedMVar
            if wDestroyed
               then done
               else do
                  disable stopBatchButton
                  enableWids wids
                  enableWidsUponSelection lb goalSpecificWids
                  batchStatusLabel # text "Batch mode stopped\n\n"
                  batchCurrentGoalLabel # text "--"
                  st <- Conc.readMVar stateMVar
                  updateDisplay st True lb statusLabel timeEntry
                                optionsEntry axiomsLb
                  done)
      +> (help >>> do
            createTextDisplay (prName ++ " Help")
                              (proverHelpText atpFun)
                              [size (80, 30)]
            done)
      +> (saveConfiguration >>> do
            s <- Conc.readMVar stateMVar
            let cfgText = show $ printCfgText $ configsMap s
            createTextSaveDisplay
                (prName ++ " Configuration for Theory " ++ thName)
                (thName ++ (theoryConfiguration $ fileExtensions atpFun))
                cfgText
            done)
      ))
  sync ( (exit >>> destroy main)
      +> (closeWindow >>> do
                 Conc.putMVar windowDestroyedMVar ()
                 cleanupThread mVar_batchId
                 destroy main)
       )
  s <- Conc.takeMVar stateMVar
  let Result _ proof_stats = revertRenamingOfLabels s $
          map (\g -> let res = Map.lookup g (configsMap s)
                         g' = Map.findWithDefault
                                        (error ("Lookup of name failed: (1) "
                                                ++"should not happen \""
                                                ++g++"\""))
                                        g (namesMap s)
                     in maybe (openProof_status g' prName $ proof_tree s)
                              proof_status
                              res)
                    (map AS_Anno.senAttr $ goalsList s)
  -- diags should not be plainly shown by putStrLn here
  maybe (fail "reverse translation of names failed") return proof_stats

  where
    cleanupThread mVar_TId =
         Conc.tryTakeMVar mVar_TId >>= maybe (return ()) Conc.killThread

    windowDestroyed sMVar =
       Conc.yield >>
       Conc.tryTakeMVar sMVar >>=
         maybe (return False)  (\ un -> Conc.putMVar sMVar un >> return True)

    isBatchModeRunning tIdMVar =
       Conc.tryTakeMVar tIdMVar >>=
        maybe (return False) (\ tId -> Conc.putMVar tIdMVar tId >> return True)

    noGoalSelected = errorMess "Please select a goal first."
    prepareLP prS s goal inclProvedThs =
       let (beforeThis, afterThis) =
              splitAt (maybe (error "GUI.GenericATP: goal shoud be found") id $
                             findIndex (\sen -> AS_Anno.senAttr sen == goal)
                                  (goalsList s))
                       (goalsList s)
           proved = filter (\sen-> checkGoal (configsMap s)
                                       (AS_Anno.senAttr sen)) beforeThis
       in if inclProvedThs
             then (head afterThis,
                   foldl (\lp provedGoal ->
                     (atpInsertSentence atpFun)
                       lp (provedGoal{AS_Anno.isAxiom = True}))
                         prS
                         (reverse proved))
             else (maybe (error ("GUI.GenericATP.prepareLP: Goal "++goal++
                                 " not found!!"))
                         id (find ((==goal) . AS_Anno.senAttr) (goalsList s)),
                   prS)
    setCurrentGoalLabel batchLabel s = batchLabel # text (take 65 s)
    removeFirstDot [] = error "GenericATP: no extension given"
    removeFirstDot e@(h:ext) =
       case h of
            '.' -> ext
            _   -> e

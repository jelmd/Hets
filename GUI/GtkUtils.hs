{- |
Module      :  $Header$
Description :  Access to the .glade files stored as strings inside the binary
Copyright   :  (c) Thiemo Wiedemeyer, Uni Bremen 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  raider@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable

This module provides the ability to store xml stings in a temporary file to load
it with gtk2hs. This is needed, because gtk2hs needs glade files for input, but
we want to distribute them within the binary.
-}

module GUI.GtkUtils
  ( getGladeXML
  , startMainLoop
  , stopMainLoop
  -- Usefull windows
  , infoDialog
  , errorDialog
  , warningDialog
  , questionDialog

  , fileOpenDialog
  , fileSaveDialog

  , listChoice
  , textView

  , displayTheory
  , displayTheoryWithWarning

  -- Frequently used functions
  , setListData
  )
  where

import Graphics.UI.Gtk
import Graphics.UI.Gtk.Glade
import Graphics.UI.Gtk.ModelView as MV

import qualified GUI.Glade.Utils as Utils

import Static.GTheory (G_theory)
import Common.DocUtils (showDoc)

import Control.Concurrent (forkIO)

import System.Directory (removeFile, getTemporaryDirectory, doesFileExist)
import System.FilePath (takeFileName, takeDirectory)
import System.IO (hFlush, hClose, hPutStr, openTempFile)

import Monad (mapM_)

-- Gtk Utils

-- | Returns a GladeXML Object of a xmlstring.
getGladeXML :: (String, String) -> IO GladeXML
getGladeXML (name, xmlstr) = do
  temp <- getTemporaryDirectory
  (filename, handle) <- openTempFile temp name
  hPutStr handle xmlstr
  hFlush handle
  mxml <- xmlNew filename
  hClose handle
  removeFile filename
  case mxml of
    Just xml -> return xml
    Nothing -> error "GtkUtils: Can't load xml string."

-- | Starts the gtk main event loop in a thread
startMainLoop :: IO ()
startMainLoop = do
  forkIO $ do
    unsafeInitGUIForThreadedRTS
    mainGUI
  return ()

stopMainLoop :: IO ()
stopMainLoop = postGUISync $ do
  mainQuit

-- Usefull windows

-- Dialogs for messages

dialog :: MessageType -- ^ Dialogtype
       -> String -- ^ Title
       -> String -- ^ Message
       -> Maybe (IO()) -- ^ Action on Ok, Yes
       -> IO Bool
dialog messageType title message mAction = do
  dlg <- case messageType of
    MessageInfo ->
      messageDialogNew Nothing [] messageType ButtonsOk message
    MessageWarning ->
      messageDialogNew Nothing [] messageType ButtonsYesNo message
    MessageQuestion ->
      messageDialogNew Nothing [] messageType ButtonsYesNo message
    _ ->
      messageDialogNew Nothing [] messageType ButtonsOk message
  set dlg [windowTitle := title]

  response <- dialogRun dlg
  choice <- case response of
    ResponseOk -> return True
    ResponseYes -> return True
    _ -> return False

  widgetDestroy dlg
  case choice of
    True -> case mAction of
      Just action -> do
        forkIO $ action
        return choice
      Nothing -> return choice
    False -> return choice

-- | create a window which displays a given text
infoDialog :: String -- ^ Title
           -> String -- ^ Message
           -> IO ()
infoDialog title message = postGUISync $ do
  dialog MessageInfo title message Nothing
  return ()

-- | create a window which displays a given error
errorDialog :: String -- ^ Title
            -> String -- ^ Message
            -> IO ()
errorDialog title message = postGUISync $ do
  dialog MessageError title message Nothing
  return ()

-- | create a window which displays a given warning and ask for continue
warningDialog :: String -- ^ Title
              -> String -- ^ Message
              -> Maybe (IO ()) -- ^ Action on Ok
              -> IO Bool
warningDialog title message mAction =
  postGUISync $ dialog MessageWarning title message mAction

-- | create a window which displays a given question
questionDialog :: String  -- ^ Title
               -> String  -- ^ Message
               -> Maybe (IO ()) -- ^ Action on Yes
               -> IO Bool
questionDialog title message mAction =
  postGUISync $ dialog MessageQuestion title message mAction

-- Filedialogs for opening and saving

fileDialog :: FileChooserAction -- ^ Action
           -> FilePath -- ^ Defaultname for file
           -> [(String, [String])] -- ^ Filter (name, pattern list)
           -> Maybe (FilePath -> IO ()) -- ^ Action on open
           -> IO (Maybe FilePath)
fileDialog fAction fname filters mAction = do
  dlg <- case fAction of
    FileChooserActionOpen -> do
      dlg' <-fileChooserDialogNew Nothing Nothing FileChooserActionOpen
                                  [ (stockCancel, ResponseCancel)
                                  , (stockOpen,   ResponseAccept)]
      fileChooserSetCurrentFolder dlg' $ takeDirectory fname 
      fileChooserSetFilename dlg' $ takeFileName fname
      return dlg'
    FileChooserActionSave -> do
      dlg' <- fileChooserDialogNew Nothing Nothing FileChooserActionSave
                                   [ (stockCancel, ResponseCancel)
                                   , (stockSave,   ResponseAccept)]
      fileChooserSetCurrentFolder dlg' $ takeDirectory fname
      fileChooserSetCurrentName dlg' $ takeFileName fname
      return dlg'
    _ -> error "FileDialog: Wrong Type"

  mapM_ (\ (name, pattern) -> do
          fileFilter <- fileFilterNew
          mapM_ (fileFilterAddPattern fileFilter) pattern
          fileFilterSetName fileFilter name
          fileChooserAddFilter dlg fileFilter
        ) filters

  response <- dialogRun dlg
  ret <- case response of
    ResponseCancel -> return Nothing
    ResponseAccept -> do
      mpath <- fileChooserGetFilename dlg
      case mpath of
        Just path -> do
          exist <- doesFileExist path
          answer <- case exist of
            True -> dialog MessageQuestion "File already exist"
                           "Are you sure to overwrite existing file?" Nothing
            False -> return True
          case answer of
            True -> case mAction of
              Just action -> do
                action path
                return mpath
              Nothing -> return mpath
            False -> return Nothing
        Nothing -> return Nothing
    _ -> return Nothing
  widgetDestroy dlg
  return ret

fileOpenDialog :: FilePath -- ^ Defaultname for file
               -> [(String, [String])] -- ^ Filter (name, pattern list)
               -> Maybe (FilePath -> IO ()) -- ^ Action on open
               -> IO (Maybe FilePath)
fileOpenDialog p f a = postGUISync $ fileDialog FileChooserActionOpen p f a

fileSaveDialog :: FilePath -- ^ Defaultname for file
               -> [(String, [String])] -- ^ Filter (name, pattern list)
               -> Maybe (FilePath -> IO ()) -- ^ Action on save
               -> IO (Maybe FilePath)
fileSaveDialog p f a = postGUISync $ fileDialog FileChooserActionSave p f a


-- | create a window with title and list of options, return selected option
listChoice :: String -- ^ Title
           -> [String] -- ^ Rows to display
           -> IO (Maybe Int) -- ^ Selected row
listChoice title items = postGUISync $ do
  xml     <- getGladeXML Utils.get
  -- get objects
  dlg     <- xmlGetWidget xml castToDialog "ListView"
  trvList <- xmlGetWidget xml castToTreeView "trvList"

  set dlg [windowTitle := title]
  store <- setListData trvList (\ a -> a) items
  selector <- MV.treeViewGetSelection trvList
  MV.treeSelectionSetMode selector MV.SelectionSingle
  mIter <- MV.treeModelGetIterFirst store
  case mIter of
    Just iter -> MV.treeSelectionSelectIter selector iter
    Nothing -> return ()

  dialogAddButton dlg stockCancel ResponseCancel
  dialogAddButton dlg stockOk ResponseOk

  response <- dialogRun dlg
  ret <- case response of
    ResponseCancel -> return Nothing
    ResponseOk -> do
      (row:_):_ <- MV.treeSelectionGetSelectedRows selector
      return $ Just row
    _ -> return Nothing
  widgetDestroy dlg
  return ret

setListData :: MV.TreeView -> (a -> String) -> [a] -> IO (MV.ListStore a)
setListData view getT listData = do
  store <- MV.listStoreNew listData
  MV.treeViewSetModel view store
  MV.treeViewSetHeadersVisible view False
  ren <- MV.cellRendererTextNew
  col <- MV.treeViewColumnNew
  MV.treeViewColumnPackStart col ren True
  MV.cellLayoutSetAttributes col ren store $ \row -> [ MV.cellText := getT row ]
  MV.treeViewAppendColumn view col
  return store

-- | Display text in an uneditable, scrollable editor. Not blocking!
textView :: String -- ^ Title
         -> String -- ^ Message
         -> Maybe (FilePath) -- ^ Filename
         -> IO ()
textView title message mfile = postGUIAsync $ do
  xml     <- getGladeXML Utils.get
  -- get objects
  dlg    <- xmlGetWidget xml castToDialog "TextView"
  tvText <- xmlGetWidget xml castToTextView "tvText"

  set dlg [windowTitle := title]
  buffer <- textViewGetBuffer tvText
  textBufferInsertAtCursor buffer message

  tagTable <- textBufferGetTagTable buffer
  font <- textTagNew Nothing
  set font [ textTagFont := "FreeMono" ]
  textTagTableAdd tagTable font
  start <- textBufferGetStartIter buffer
  end <- textBufferGetEndIter buffer
  textBufferApplyTag buffer font start end

  case mfile of
    Just file -> do
      btnSave <- dialogAddButton dlg stockSave ResponseNone
      onClicked btnSave $ do
        fileDialog FileChooserActionSave file
                   [("Nothing", ["*"]), ("Text", ["*.txt"])]
                   $ Just (\ filepath -> writeFile filepath message)
        return ()
      return ()
    Nothing -> return ()

  btnClose <- dialogAddButton dlg stockClose ResponseNone
  onClicked btnClose $ widgetDestroy dlg

  widgetShow dlg
  return ()

-- | displays a theory in a window
displayTheory :: String -- ^ Kind of theory
              -> String -- ^ Name of theory
              -> G_theory -- ^ Theory
              -> IO ()
displayTheory kind name gth =
  textView ( kind ++ " of " ++ name) (showDoc gth "\n") $ Just $ name ++ ".het"

-- | displays a theory with warning in a window
displayTheoryWithWarning :: String -- ^ Kind of theory
                         -> String -- ^ Name of theory
                         -> String -- ^ Warning
                         -> G_theory -- ^ Theory
                         -> IO ()
displayTheoryWithWarning kind name warning gth =
  textView (kind ++ " of " ++ name) (warning ++ (showDoc gth "\n"))
           $ Just $ name ++ ".het"

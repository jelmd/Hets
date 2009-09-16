{- |
Module      :$Header$
Description : after parsing XML message a list of XMLcommands is produced,
              containing commands that need to be executed
Copyright   : uni-bremen and DFKI
Licence     : similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  : r.pascanu@jacobs-university.de
Stability   : provisional
Portability : portable

PGIP.XMLstate contains the description of the XMLstate and a function
that produces such a state
-}

module PGIP.XMLstate where

import Data.List(find, intercalate)
import Data.Time.Clock.POSIX(getPOSIXTime)
import System.IO(Handle)

import Common.Utils(getEnvDef, trim)
import Text.XML.Light
import PGIP.MarkPgip(genQName)

-- generates a pgipelem element that contains the input text
genPgipElem :: String -> Content
genPgipElem str =
   Elem Element {
     elName    = genQName "pgipelem",
     elAttribs = [],
     elContent = [Text $ CData CDataRaw str Nothing],
     elLine    = Nothing
   }

-- generates a normalresponse element that has a pgml element
-- containing the output text
genNormalResponse :: String -> Content
genNormalResponse str =
 {-let pgmlText = Elem Element {
                   elName = genQName "atom",
                   elAttribs = [],
                   elContent = [Text $ CData CDataRaw str Nothing],
                   elLine = Nothing }
 in-}
  Elem Element {
          elName = genQName "normalresponse",
          elAttribs = [],
          elContent = [ Elem Element {
                         elName = genQName "pgml",
                         elAttribs = [Attr {
                                       attrKey = genQName "area",
                                       attrVal = "message"} ],
                         elContent =  [Text $ CData CDataRaw str Nothing],
                                      -- [pgmlText],
                         elLine = Nothing } ],
          elLine = Nothing }

-- same as above, just for an error instead of normal output
genErrorResponse :: Bool -> String -> Content
genErrorResponse fatality str =
  Elem Element {
    elName = genQName "errorresponse",
    elAttribs = [ Attr { attrKey = genQName "fatality",
                         attrVal = "fatal" } | fatality ],
    elContent = [ Elem Element {
                    elName = genQName "pgmltext",
                    elAttribs = [],
                    elContent = [Text $ CData CDataRaw str Nothing],
                    elLine = Nothing } ],
    elLine = Nothing
  }

-- adds one element at the end of the content of the xml packet that represents
-- the current output of the interface to the broker
addToContent :: CMDL_PgipState -> Content -> CMDL_PgipState
addToContent pgData cont =
  pgData {
    xmlContent = case xmlContent pgData of
                  Elem e -> Elem e { elContent = elContent e ++ [cont] }
                  _      -> xmlContent pgData
  }

-- adds an ready element at the end of the xml packet that represents the
-- current output of the interface to the broker
addReadyXml :: CMDL_PgipState -> CMDL_PgipState
addReadyXml pgData =
  let el_ready = Elem Element {
                   elName = genQName "ready",
                   elAttribs = [],
                   elContent = [],
                   elLine = Nothing }
   in addToContent pgData el_ready

-- | State that keeps track of the comunication between Hets and the Broker
data CMDL_PgipState = CMDL_PgipState {
                    pgip_id            :: String,
                    name               :: String,
                    seqNb              :: Int,
                    refSeqNb           :: Maybe String,
                    theMsg             :: String,
                    xmlContent         :: Content,
                    hout               :: Handle,
                    hin                :: Handle,
                    stop               :: Bool,
                    resendMsgIfTimeout :: Bool,
                    useXML             :: Bool,
                    maxWaitTime        :: Int,
                    quietOutput        :: Bool
                    }

-- | Generates an empty CMDL_PgipState
genCMDLPgipState :: Bool -> Handle -> Handle -> Int -> IO CMDL_PgipState
genCMDLPgipState swXML h_in h_out timeOut =
  do
   pgId <- genPgipID
   return CMDL_PgipState {
     pgip_id            = pgId,
     name               = "Hets",
     quietOutput        = False,
     seqNb              = 1,
     refSeqNb           = Nothing,
     theMsg             = [],
     xmlContent         = Elem blank_element { elName = genQName "pgip" },
     hin                = h_in,
     hout               = h_out,
     stop               = False,
     resendMsgIfTimeout = True,
     useXML             = swXML,
     maxWaitTime        = timeOut
     }

-- | Generates the id of the session between Hets and the Broker
genPgipID :: IO String
genPgipID =
  do
   t1 <- getEnvDef "HOSTNAME" ""
   t2 <- getEnvDef "USER" ""
   t3 <- getPOSIXTime
   return $ t1 ++ "/" ++ t2 ++ "/" ++ show t3

-- | Concatenates the input string to the message stored in the state
addToMsg :: String -> String -> CMDL_PgipState -> CMDL_PgipState
addToMsg str errStr pgD =
  let strings = [theMsg pgD, str, errStr]
   in pgD { theMsg = intercalate "\n" $ filter (not . null) strings }

-- | Resets the content of the message stored in the state
resetMsg :: String -> CMDL_PgipState -> CMDL_PgipState
resetMsg str pgD = pgD {
    theMsg = str,
    xmlContent = convertPgipStateToXML pgD
  }

-- extracts the xml package in XML.Light format (namely the Content type)
convertPgipStateToXML :: CMDL_PgipState -> Content
convertPgipStateToXML pgipData =
  let baseElem = Element {
                   elName     = genQName "pgip",
                   elAttribs  = [ Attr {
                                  attrKey = genQName "tag",
                                  attrVal = name pgipData }
                                , Attr {
                                  attrKey = genQName "class",
                                  attrVal = "pg"}
                                , Attr {
                                  attrKey = genQName "id",
                                  attrVal = pgip_id pgipData }
                                , Attr {
                                  attrKey = genQName "seq",
                                  attrVal = show $ seqNb pgipData} ],
                   elContent  = [],
                   elLine     = Nothing}
   in case refSeqNb pgipData of
    Nothing -> Elem baseElem
    Just v  -> Elem $ baseElem {
                 elAttribs = Attr { attrKey = genQName "refseq",
                                    attrVal = v } : elAttribs baseElem
               }

-- | List of all possible commands inside an XML packet
data CMDL_XMLcommands =
   XML_Execute String
 | XML_Exit
 | XML_ProverInit
 | XML_Askpgip
 | XML_StartQuiet
 | XML_StopQuiet
 | XML_OpenGoal String
 | XML_CloseGoal String
 | XML_GiveUpGoal String
 | XML_Unknown String
 | XML_ParseScript String
 | XML_Undo
 | XML_Redo
 | XML_Forget String
 | XML_OpenTheory String
 | XML_CloseTheory String
 | XML_CloseFile String
 | XML_LoadFile String deriving (Eq,Show)

-- extracts the refrence number of a xml packet (given as a string)
getRefseqNb :: String -> Maybe String
getRefseqNb input =
  let xmlTree = parseXML input
      elRef = find (\ x -> case x of
                              Elem dt -> qName (elName dt) == "pgip"
                              _       -> False) xmlTree
   in case elRef of
        Nothing -> Nothing
        Just el -> case el of
                     Elem dt -> case find (\x -> qName (attrKey x) == "seq") $
                                     elAttribs dt of
                                  Nothing -> Nothing
                                  Just elatr -> Just $ attrVal elatr
                     _       -> Nothing


-- parses the xml message creating a list of commands that it needs to
-- execute
parseXMLTree :: [Content] -> [CMDL_XMLcommands] -> [CMDL_XMLcommands]
parseXMLTree  xmltree acc =
  case xmltree of
    []             -> acc
    (Elem info):ls -> case parseXMLElement info of
                        Just c  -> parseXMLTree ls (c:acc)
                        Nothing -> parseXMLTree (elContent info ++ ls) acc
    _:ls           -> parseXMLTree ls acc

parseXMLElement :: Element -> Maybe CMDL_XMLcommands
parseXMLElement info =
  case qName $ elName info of
    "proverinit"   -> Just $ XML_ProverInit
    "proverexit"   -> Just $ XML_Exit
    "startquiet"   -> Just $ XML_StartQuiet
    "stopquiet"    -> Just $ XML_StopQuiet
    "opengoal"     -> Just $ XML_OpenGoal cnt
    "proofstep"    -> Just $ XML_Execute cnt
    "closegoal"    -> Just $ XML_CloseGoal cnt
    "giveupgoal"   -> Just $ XML_GiveUpGoal cnt
    "spurioscmd"   -> Just $ XML_Execute cnt
    "dostep"       -> Just $ XML_Execute cnt
    "editobj"      -> Just $ XML_Execute cnt
    "undostep"     -> Just $ XML_Undo
    "redostep"     -> Just $ XML_Redo
    "forget"       -> Just $ XML_Forget cnt
    "opentheory"   -> Just $ XML_Execute cnt
    "theoryitem"   -> Just $ XML_Execute cnt
    "closetheory"  -> Just $ XML_CloseTheory cnt
    "closefile"    -> Just $ XML_CloseFile cnt
    "loadfile"     -> Just $ XML_LoadFile cnt
    "askpgip"      -> Just $ XML_Askpgip
    "parsescript"  -> Just $ XML_ParseScript cnt
    _              -> Nothing
  where
    cnt = case head $ elContent info of
            Text smtxt -> cdData smtxt
            _          -> []

-- | Given a packet (a normal string or a xml formated string), the function
-- converts it into a list of commands
parseMsg :: CMDL_PgipState -> String -> [CMDL_XMLcommands]
parseMsg st input =
  if useXML st
   then parseXMLTree (parseXML input) []
   else concatMap (\ x -> [ XML_Execute x | not $ null $ trim x ]) $ lines input
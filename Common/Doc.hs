{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

document data type for displaying (heterogenous) CASL specifications
at least as plain text and latex (and maybe in html as well)

inspired by John Hughes's and Simon Peyton Jones's Pretty Printer Combinators
in "Text.PrettyPrint.HughesPJ", Thomas Hallgren's
<http://www.cse.ogi.edu/~hallgren/Programatica/tools/pfe.cgi?PrettyDoc>
Daan Leijen's PPrint: A prettier printer 2001, Olaf Chiti's
Pretty printing with lazy Dequeues 2003
-}

module Common.Doc
    ( -- * The document type
      Doc            -- Abstract
      -- * Primitive Documents
    , empty
    , space
    , semi
    , comma
    , colon
    , equals
    , lparen
    , rparen
    , lbrack
    , rbrack
    , lbrace
    , rbrace
      -- * Converting strings into documents
    , text
    , literalDoc
      -- * Wrapping documents in delimiters
    , parens
    , brackets
    , specBraces
    , quotes
    , doubleQuotes
      -- * Combining documents
    , (<>)
    , (<+>)
    , hcat
    , hsep
    , ($+$)
    , ($++$)
    , vcat
    , vsep
    , sep
    , cat
    , fsep
    , fcat
    , punctuate
    , flushRight
      -- * keywords
    , keyword
    , topKey
    , indexed
    , structId
      -- * symbols
    , dot
    , bullet
    , defn
    , less
    , greater
    , lambda
    , mapsto
    , funArrow
    , pfun
    , cfun
    , pcfun
    , exequal
    , forallDoc
    , exists
    , unique
    , cross
    , bar
    , notDoc
    , inDoc
    , andDoc
    , orDoc
    , implies
    , equiv
      -- * docifying annotations and ids
    , annoDoc
    , idDoc
    , idApplDoc
      -- * transforming to existing formats
    , toText
    , toLatex
      -- * a class
    , Pretty(..)
      -- * manipulating documents
    , changeGlobalAnnos
    , rmTopKey
    ) where

import Common.Id
import Common.Keywords
import Common.AS_Annotation
import Common.GlobalAnnotations
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Pretty as Pretty
import Common.LaTeX_funs
import Common.ConvertLiteral
import Common.Prec
import Data.Char
import Data.List

infixl 6 <>
infixl 6 <+>
infixl 5 $+$
infixl 5 $++$

-- * the data type

data TextKind =
    IdKind | IdSymb | Symbol | Comment | Keyword | TopKey | Indexed | StructId
    | Native

data Format = Small | FlushRight

data ComposeKind
    = Vert   -- ($+$) (no support for $$!)
    | Horiz  -- (<>)
    | HorizOrVert -- either Horiz or Vert
    | Fill
      deriving Eq

data Doc
    = Empty          -- creates an empty line if composed vertically
    | AnnoDoc Annotation -- we know how to print annotations
    | IdDoc Id           -- for plain ids outside applications
    | IdApplDoc Id [Doc] -- for mixfix applications and literal terms
    | Text TextKind String -- non-empty and no white spaces inside
    | Cat ComposeKind [Doc]
    | Attr Format Doc      -- for annotations
    | LiteralDoc Pretty.Doc  -- for backward compatibility only
    | ChangeGlobalAnnos (GlobalAnnos -> GlobalAnnos) Doc

instance Show Doc where
    showsPrec _ doc cont =
        Pretty.renderStyle' cont Pretty.style $ toText emptyGlobalAnnos doc

isEmpty :: Doc -> Bool
isEmpty d = case d of
              Empty -> True
              Cat _ [] -> True
              _ -> False

-- * the visible interface

empty :: Doc                 -- ^ An empty document
empty = Empty

text :: String -> Doc
text = Text IdKind

semi :: Doc                 -- ^ A ';' character
semi = text ";"

comma :: Doc                 -- ^ A ',' character
comma = text ","

colon :: Doc                 -- ^ A ':' character
colon = symbol colonS

-- the only legal white space within Text
space :: Doc                 -- ^ A horizontal space (omitted at end of line)
space = text " "

equals :: Doc                 -- ^ A '=' character
equals = symbol equalS

-- use symbol for signs that need to be put in mathmode for latex
symbol :: String -> Doc
symbol = Text Symbol

-- for text within comments
commentText :: String -> Doc
commentText = Text Comment

-- put this string into math mode for latex and don't escape it
native :: String -> Doc
native = Text Native

-- leave this string entirely untouched for old latex bits
literalDoc :: Pretty.Doc -> Doc
literalDoc = LiteralDoc

lparen, rparen, lbrack, rbrack, lbrace, rbrace, quote, doubleQuote :: Doc

lparen = symbol "("
rparen = symbol ")"
lbrack = symbol "["
rbrack = symbol "]"
lbrace = symbol "{"  -- to allow for latex translations
rbrace = symbol "}"
quote = symbol "\'"
doubleQuote = symbol "\""

parens :: Doc -> Doc     -- ^ Wrap document in @(...)@
parens d = hcat [lparen, d, rparen]

brackets :: Doc -> Doc     -- ^ Wrap document in @[...]@
brackets d = hcat [lbrack, d, rbrack]

braces :: Doc -> Doc     -- ^ Wrap document in @{...}@
braces d = hcat [lbrace, d, rbrace]

specBraces :: Doc -> Doc     -- ^ Wrap document in @{...}@
specBraces d = cat [addLBrace d, rbrace]

-- | move the opening brace inwards
addLBrace :: Doc -> Doc
addLBrace d = case d of
    Cat k (e : r) -> Cat k $ addLBrace e : r
    _ -> lbrace <> d

quotes :: Doc -> Doc     -- ^ Wrap document in @\'...\'@
quotes d = hcat [quote, d, quote]

doubleQuotes :: Doc -> Doc     -- ^ Wrap document in @\"...\"@
doubleQuotes d = hcat [doubleQuote, d, doubleQuote]

(<>) :: Doc -> Doc -> Doc      -- ^Beside
a <> b = hcat [a, b]

rmEmpties :: [Doc] -> [Doc]
rmEmpties = filter (not . isEmpty)

hcat :: [Doc] -> Doc          -- ^List version of '<>'
hcat = Cat Horiz . rmEmpties

(<+>) :: Doc -> Doc -> Doc     -- ^Beside, separated by space
a <+> b = hsep [a, b]

punctuate :: Doc -> [Doc] -> [Doc]
punctuate d l = case l of
     x : r@(_ : _) -> (x <> d) : punctuate d r
     _ -> l

hsep :: [Doc] -> Doc         -- ^List version of '<+>'
hsep = Cat Horiz . punctuate space . rmEmpties

($+$) :: Doc -> Doc -> Doc;    -- ^Above, without dovetailing.
a $+$ b = vcat [a, b]

-- | vertical composition with a specified number of blank lines
aboveWithNLs :: Int -> Doc -> Doc -> Doc
aboveWithNLs n d1 d2 = if isEmpty d2 then d1 else
             if isEmpty d1 then d2 else
             d1 $+$ foldr ($+$) d2 (replicate n $ text "")

-- | vertical composition with one blank line
($++$) :: Doc -> Doc -> Doc
($++$) = aboveWithNLs 1

-- | list version of '($++$)'
vsep :: [Doc] -> Doc
vsep = foldr ($++$) empty

vcat :: [Doc] -> Doc          -- ^List version of '$+$'
vcat = Cat Vert . rmEmpties

cat    :: [Doc] -> Doc          -- ^ Either hcat or vcat
cat = Cat HorizOrVert . rmEmpties

sep    :: [Doc] -> Doc          -- ^ Either hsep or vcat
sep = Cat HorizOrVert . punctuate space . rmEmpties

fcat   :: [Doc] -> Doc          -- ^ \"Paragraph fill\" version of cat
fcat = Cat Fill . rmEmpties

fsep   :: [Doc] -> Doc          -- ^ \"Paragraph fill\" version of sep
fsep = Cat Fill . punctuate space . rmEmpties

keyword, topKey, indexed, structId :: String -> Doc
keyword = Text Keyword
indexed = Text Indexed
structId = Text StructId
topKey = Text TopKey

lambdaSymb :: String
lambdaSymb = "\\"

-- | docs possibly rendered differently for Text or LaTeX
dot, bullet, defn, less, greater, lambda, mapsto, funArrow, pfun, cfun, pcfun,
   exequal, forallDoc, exists, unique, cross, bar, notDoc, inDoc, andDoc,
   orDoc, implies, equiv :: Doc

dot = text dotS
bullet = symbol dotS
defn = symbol defnS
less = symbol lessS
greater = symbol greaterS
lambda = symbol lambdaSymb
mapsto = symbol mapsTo
funArrow = symbol funS
pfun = symbol pFun
cfun = symbol contFun
pcfun = symbol pContFun
exequal = symbol exEqual
forallDoc = symbol forallS
exists = symbol existsS
unique = symbol existsUnique
cross = symbol prodS
bar = symbol barS
notDoc = symbol notS
inDoc = symbol inS
andDoc = symbol lAnd
orDoc = symbol lOr
implies = symbol implS
equiv = symbol equivS

-- | we know how to print annotations
annoDoc :: Annotation -> Doc
annoDoc = AnnoDoc

-- | for plain ids outside applications
idDoc :: Id -> Doc
idDoc = IdDoc

-- | for mixfix applications and literal terms (may print \"\" for empty)
idApplDoc :: Id -> [Doc] -> Doc
idApplDoc = IdApplDoc

-- | put document as far to the right as fits (for annotations)
flushRight :: Doc -> Doc
flushRight = Attr FlushRight

small :: Doc -> Doc
small = Attr Small

-- * folding stuff

data DocRecord a = DocRecord
    { foldEmpty :: Doc -> a
    , foldAnnoDoc :: Doc -> Annotation -> a
    , foldIdDoc :: Doc -> Id -> a
    , foldIdApplDoc :: Doc -> Id -> [a] -> a
    , foldText :: Doc -> TextKind -> String -> a
    , foldCat :: Doc -> ComposeKind -> [a] -> a
    , foldAttr :: Doc -> Format -> a -> a
    , foldLiteralDoc :: Doc -> Pretty.Doc -> a
    , foldChangeGlobalAnnos :: Doc -> (GlobalAnnos -> GlobalAnnos) -> a -> a
    }

foldDoc :: DocRecord a -> Doc -> a
foldDoc r d = case d of
    Empty -> foldEmpty r d
    AnnoDoc a -> foldAnnoDoc r d a
    IdDoc i -> foldIdDoc r d i
    IdApplDoc i l -> foldIdApplDoc r d i $ map (foldDoc r) l
    Text k s -> foldText r d k s
    Cat k l -> foldCat r d k $ map (foldDoc r) l
    Attr a e -> foldAttr r d a $ foldDoc r e
    LiteralDoc o -> foldLiteralDoc r d o
    ChangeGlobalAnnos f e -> foldChangeGlobalAnnos r d f $ foldDoc r e

idRecord :: DocRecord Doc
idRecord = DocRecord
    { foldEmpty = \ _ -> Empty
    , foldAnnoDoc = \ _ -> AnnoDoc
    , foldIdDoc = \ _ -> IdDoc
    , foldIdApplDoc = \ _ -> IdApplDoc
    , foldText = \ _ -> Text
    , foldCat = \ _ -> Cat
    , foldAttr = \ _ -> Attr
    , foldLiteralDoc = \ _ -> LiteralDoc
    , foldChangeGlobalAnnos = \ _ -> ChangeGlobalAnnos
    }

anyRecord :: DocRecord a
anyRecord = DocRecord
    { foldEmpty = error "anyRecord.Empty"
    , foldAnnoDoc = error "anyRecord.AnnoDoc"
    , foldIdDoc = error "anyRecord.IdDoc"
    , foldIdApplDoc = error "anyRecord.IdApplDoc"
    , foldText = error "anyRecord.Text"
    , foldCat = error "anyRecord.Cat"
    , foldAttr = error "anyRecord.Attr"
    , foldLiteralDoc = error "anyRecord.LiteralDoc"
    , foldChangeGlobalAnnos = error "anyRecord.ChangeGlobalAnnos"
    }

-- * conversion to plain text

-- | simple conversion to a standard text document
toText :: GlobalAnnos -> Doc -> Pretty.Doc
toText ga = foldDoc anyRecord
    { foldEmpty = \ _ -> Pretty.empty
    , foldText = \ _ k s -> case k of
          TopKey -> Pretty.text $ s ++ replicate (5 - length s) ' '
          _ -> Pretty.text s
    , foldCat = \ _ c -> case c of
          Vert -> Pretty.vcat
          Horiz -> Pretty.hcat
          HorizOrVert -> Pretty.cat
          Fill -> Pretty.fcat
    , foldAttr = \ _ k d -> case k of
          FlushRight -> let l = length $ show d in
            if l < 66 then Pretty.nest (66 - l) d else d
          _ -> d
    , foldLiteralDoc = \ _ d -> d
    , foldChangeGlobalAnnos = \ _ _ d -> d
    } . codeOut ga Nothing Map.empty

-- * conversion to latex

toLatex :: GlobalAnnos -> Doc -> Pretty.Doc
toLatex ga = let dm = Map.map (Map.! DF_LATEX) .
                      Map.filter (Map.member DF_LATEX) $ display_annos ga
    in foldDoc (toLatexRecord False)
           . makeSmallMath False False . codeOut ga (Just DF_LATEX) dm

-- avoid too many tabs
toLatexRecord :: Bool -> DocRecord Pretty.Doc
toLatexRecord tab = anyRecord
    { foldEmpty = \ _ -> Pretty.empty
    , foldText = \ _ k s -> textToLatex False k s
    , foldCat = \ (Cat c os) _ _ ->
          if any isNative os then Pretty.hcat $
             latex_macro "{\\Ax{"
             : map (foldDoc (toLatexRecord False)
                       { foldText = \ _ k s ->
                          case k of
                            Native -> Pretty.sp_text (axiom_width s) s
                            IdKind | s == " " ->
                                Pretty.sp_text (axiom_width s) "\\,"
                            _ -> textToLatex False k s
                        }) os
              ++ [latex_macro "}}"]
          else case os of
               [] -> Pretty.empty
               [d] -> foldDoc (toLatexRecord tab) d
               d : r -> (if tab && c /= Horiz then
                             (latex_macro setTab Pretty.<>)
                         . (latex_macro startTab Pretty.<>)
                         . (Pretty.<> latex_macro endTab)
                        else id)
                        $ (case c of
                             Vert -> Pretty.vcat
                             Horiz -> Pretty.hcat
                             HorizOrVert -> Pretty.cat
                             Fill -> Pretty.fcat)
                        $ case c of
                            Vert -> map (foldDoc $ toLatexRecord False) os
                            _ -> foldDoc (toLatexRecord False) d :
                                     map (foldDoc $ toLatexRecord True) r
    , foldAttr = \ o k d -> case k of
          FlushRight -> flushright d
          Small -> case o of
              Attr Small (Text j s) -> textToLatex True j s
              _ -> makeSmallLatex True d
    , foldLiteralDoc = \ _ d -> d
    , foldChangeGlobalAnnos = \ _ _ d -> d
    }

-- | move a small attribute inwards but not into mathmode bits
makeSmallMath :: Bool -> Bool -> Doc -> Doc
makeSmallMath smll math = let rec = makeSmallMath smll math in
    foldDoc idRecord
    { foldAttr = \ (Attr k d) _ _ -> case k of
                       Small -> makeSmallMath True math d
                       _ -> Attr k $ makeSmallMath smll math d
    , foldCat = \ o@(Cat c l) _ _ ->
                    if any isNative l then
                        (if smll then Attr Small else id)
                        -- flatten math mode bits
                           $ Cat Horiz $ map
                                 (makeSmallMath False True . rmSpace) l
                    else if math then Cat Horiz
                         $ map (makeSmallMath False True) l
                    else if smll && allHoriz o then
                    -- produce fewer small blocks with wrong size though
                             Attr Small $ Cat Horiz $
                              map (makeSmallMath False math) l
                         else Cat c $ map rec l
    , foldText = \ d _ _ -> if smll then Attr Small d else d
    }

-- | check for unbalanced braces
needsMathMode :: Int -> String -> Bool
needsMathMode i s = case s of
    [] -> i > 0
    c : r -> if c == '{' then needsMathMode (i + 1) r else
             if c == '}' then if i == 0 then True else
                                  needsMathMode (i - 1) r
             else needsMathMode i r

isMathLatex :: Doc -> Bool
isMathLatex d = case d of
               Text Native s -> needsMathMode 0 s
               Attr Small f -> isMathLatex f
               _ -> False

isNative :: Doc -> Bool
isNative d = case d of
               Cat Horiz [t, _] -> isMathLatex t
               _ -> isMathLatex d

-- | remove the spaces inserted by punctuate for latex macros
rmSpace :: Doc -> Doc
rmSpace d = case d of
              Cat Horiz [t, Text IdKind s] | s == " " -> t
              _ -> d

allHoriz :: Doc -> Bool
allHoriz d = case d of
               Text _ _ -> True
               Cat Horiz l -> and $ map allHoriz l
               Attr _ f -> allHoriz f
               Empty -> True
               _ -> False

makeSmallLatex :: Bool -> Pretty.Doc -> Pretty.Doc
makeSmallLatex b d =
   if b then Pretty.hcat [latex_macro startAnno, d, latex_macro endAnno]
   else d

symbolToLatex :: String -> Pretty.Doc
symbolToLatex s = Map.findWithDefault (hc_sty_axiom
                                       $ escapeLatex False s) s latexSymbols

textToLatex :: Bool -> TextKind -> String -> Pretty.Doc
textToLatex b k s = let e = escapeLatex True s in
        if elem s $ map (: []) ",;[]() "
        then makeSmallLatex b $ casl_normal_latex s
        else case k of
    IdKind -> makeSmallLatex b $ hc_sty_id e
    IdSymb -> makeSmallLatex b $ hc_sty_axiom $ escapeLatex False s
    Symbol -> makeSmallLatex b $ symbolToLatex s
    Comment -> (if b then makeSmallLatex b . casl_comment_latex
               else casl_normal_latex) e
               -- multiple spaces should be replaced by \hspace
    Keyword -> (if b then makeSmallLatex b . hc_sty_small_keyword
                else hc_sty_plain_keyword) s
    TopKey -> hc_sty_casl_keyword s
    Indexed -> hc_sty_structid_indexed s
    StructId -> hc_sty_structid s
    Native -> hc_sty_axiom s

latexSymbols :: Map.Map String Pretty.Doc
latexSymbols = Map.fromList
    [ (dotS, bullet_latex)
    , (diamondS, hc_sty_axiom "\\Diamond")
    , (percentS, hc_sty_small_keyword "\\%")
    , (percents, hc_sty_small_keyword "\\%\\%")
    , ("{", casl_normal_latex "\\{")
    , ("}", casl_normal_latex "\\}")
    , ("__", hc_sty_axiom "\\_\\_")
    , (lambdaSymb, hc_sty_axiom "\\lambda")
    , (mapsTo, mapsto_latex)
    , (funS, rightArrow)
    , (pFun, hc_sty_axiom "\\rightarrow?")
    , (contFun, cfun_latex)
    , (pContFun, pcfun_latex)
    , (exEqual, exequal_latex)
    , (forallS, forall_latex)
    , (existsS, exists_latex)
    , (existsUnique, unique_latex)
    , (prodS, hc_sty_axiom "\\times")
    , (notS, hc_sty_axiom "\\neg")
    , (inS, hc_sty_axiom "\\in")
    , (lAnd, hc_sty_axiom "\\wedge")
    , (lOr, hc_sty_axiom "\\vee")
    , (implS, hc_sty_axiom "\\Rightarrow")
    , (equivS, hc_sty_axiom "\\Leftrightarrow") ]

-- * coding out stuff

{- | transform document according to a specific display map and other
global annotations like precedences, associativities, and literal
annotations. -}
codeOut :: GlobalAnnos -> Maybe Display_format -> Map.Map Id [Token] -> Doc
        -> Doc
codeOut ga d m = foldDoc idRecord
    { foldAnnoDoc = \ _ -> small . codeOutAnno d m
    , foldIdDoc = \ _ -> codeOutId m
    , foldIdApplDoc = codeOutAppl ga d m
    , foldChangeGlobalAnnos = \ (ChangeGlobalAnnos fg e) _ _ ->
          let ng = fg ga in codeOut ng d
             (maybe m (\ f -> Map.map (Map.! f) .
                      Map.filter (Map.member f) $ display_annos ng) d) e
    }

codeToken :: String -> Doc
codeToken s = case s of
    [] -> empty
    h : _ -> (if s /= "__" && (isAlpha h || elem h "._'")
              then text else Text IdSymb) s

codeOrigId :: Map.Map Id [Token] -> Id -> [Doc]
codeOrigId m (Id ts cs _) = let
    (toks, places) = splitMixToken ts
    conv = map (codeToken . tokStr) in
    if null cs then conv ts
       else conv toks ++ codeCompIds m cs : conv places

codeCompIds :: Map.Map Id [Token] -> [Id] -> Doc
codeCompIds m cs = brackets $ fcat $ punctuate comma $ map (codeOutId m) cs

codeIdToks :: [Token] -> [Doc]
codeIdToks = map (\ t -> let s = tokStr t in
                         if isPlace t then symbol s else native s)

codeOutId :: Map.Map Id [Token] -> Id -> Doc
codeOutId m i = fcat $ case Map.lookup i m of
    Nothing -> codeOrigId m i
    Just ts -> codeIdToks ts

annoLine :: String -> Doc
annoLine w = percent <> keyword w

annoLparen :: String -> Doc
annoLparen w = percent <> keyword w <> lparen

wrapAnnoLines :: Maybe Display_format -> Doc -> [String] -> Doc -> Doc
wrapAnnoLines d a l b = case map (commentText .
          maybe id (const $ dropWhile isSpace) d) l of
    [] -> a <> b
    [x] -> hcat [a, x, b]
    ds@(x : r) -> case d of
        Nothing -> vcat $ fcat [a, x] : init r ++ [fcat [last r, b]]
        Just _ -> a <+> vcat ds <> b

percent :: Doc
percent = symbol percentS

annoRparen :: Doc
annoRparen = rparen <> percent

cCommaT :: Map.Map Id [Token] -> [Id] -> [Doc]
cCommaT m = punctuate comma . map (codeOutId m)

hCommaT :: Map.Map Id [Token] -> [Id] -> Doc
hCommaT m = hsep . cCommaT m

fCommaT :: Map.Map Id [Token] -> [Id] -> Doc
fCommaT m = fsep . cCommaT m

codeOutAnno :: Maybe Display_format -> Map.Map Id [Token] -> Annotation -> Doc
codeOutAnno d m a = case a of
    Unparsed_anno aw at _ -> case at of
        Line_anno s -> (case aw of
            Annote_word w -> annoLine w
            Comment_start -> symbol percents) <> commentText s
        Group_anno l -> case aw of
            Annote_word w -> wrapAnnoLines d (annoLparen w) l annoRparen
            Comment_start -> wrapAnnoLines d (percent <> lbrace) l
                             (rbrace <> percent)
    Display_anno i ds _ -> annoLparen displayS <> fsep
        ( fcat (codeOrigId m i) :
          map ( \ (df, s) -> percent <> text (lookupDisplayFormat df)
                <+> maybe (commentText s) (const $ codeOutId m i)
                    (Map.lookup i m)) ds) <> annoRparen
    List_anno i1 i2 i3 _ -> annoLine listS <+> hCommaT m [i1, i2, i3]
    Number_anno i _ -> annoLine numberS <+> codeOutId m i
    Float_anno i1 i2 _ -> annoLine floatingS <+> hCommaT m [i1, i2]
    String_anno i1 i2 _ -> annoLine stringS <+> hCommaT m [i1, i2]
    Prec_anno p l1 l2 _ -> annoLparen precS <>
        fsep [ braces $ fCommaT m l1
             , case p of
                 Lower -> less
                 Higher -> greater
                 BothDirections -> less <> greater
                 NoDirection -> greater <> less
             , braces $ fCommaT m l2
             ] <> annoRparen
    Assoc_anno s l _ -> annoLparen (case s of
                          ALeft -> left_assocS
                          ARight -> right_assocS)
                        <> fCommaT m l <> annoRparen
    Label l _ -> wrapAnnoLines d (annoLparen "") l annoRparen
    Semantic_anno sa _ -> annoLine $ lookupSemanticAnno sa


splitDoc :: Doc -> Maybe (Id, [Doc])
splitDoc d = case d of
    IdApplDoc i l -> Just (i, l)
    _ -> Nothing

data Weight = Weight Int Id Id Id -- top, left, right

-- print literal terms and mixfix applications
codeOutAppl :: GlobalAnnos -> Maybe Display_format -> Map.Map Id [Token]
            -> Doc -> Id -> [Doc] -> Doc
codeOutAppl ga md m origDoc _ args = case origDoc of
  IdApplDoc i@(Id ts cs _) aas ->
    let mk t = codeToken $ tokStr t
        pa = prec_annos ga
        assocs = assoc_annos ga
        precs = mkPrecIntMap pa
        p = Map.findWithDefault maxBound i $ precMap precs
        doSplit = maybe (error "doSplit") id . splitDoc
        mkList op largs cl = fsep $ codeOutId m op : punctuate comma
                             (map (codeOut ga md m) largs)
                             ++ [codeOutId m cl]
    in if isGenNumber splitDoc ga i aas then
             mk $ toNumber doSplit i aas
         else if isGenFrac splitDoc ga i aas then
             mk $ toFrac doSplit aas
         else if isGenFloat splitDoc ga i aas then
             mk $ toFloat doSplit ga aas
         else if isGenString splitDoc ga i aas then
             mk $ toString doSplit ga i aas
         else if isGenList splitDoc ga i aas then
             toMixfixList mkList doSplit ga i aas
         else if null args || length args /= placeCount i then
             codeOutId m i <> if null args then empty else
                             parens (fsep $ punctuate comma args)
         else let
             parArgs = reverse $ foldl ( \ l (arg, dc) ->
                case getWeight ga arg of
                Nothing -> dc : l
                Just (Weight q ta la ra) ->
                    let pArg = parens dc
                        d = if isBoth pa i ta then pArg else dc
                        oArg = if isDiffAssoc assocs pa i ta then pArg else d
                    in (if isLeftArg i l then
                       if checkArg ARight ga (i, p) (ta, q) ra
                       then oArg else if isSafeLhs i ta then d else pArg
                    else if isRightArg i l then
                       if checkArg ALeft ga (i, p) (ta, q) la
                       then oArg else if isInfix ta then pArg else d
                    else d) : l) [] $ zip aas args
             (fts, ncs, cFun, hFun) = case Map.lookup i m of
                            Nothing ->
                                (fst $ splitMixToken ts, cs, codeToken, fsep)
                            Just nts -> (nts, [], native, fsep)
             (rArgs, fArgs) = mapAccumL ( \ ac t ->
               if isPlace t then case ac of
                 hd : tl -> (tl, hd)
                 _ -> error "addPlainArg"
                 else (ac, cFun $ tokStr t)) parArgs fts
            in hFun $ fArgs ++ (if null ncs then [] else [codeCompIds m cs])
                                                 ++ rArgs
  _ -> error "Common.Doc.codeOutAppl"

getWeight :: GlobalAnnos -> Doc -> Maybe Weight
getWeight ga d = let
    pa = prec_annos ga
    precs = mkPrecIntMap pa
    m = precMap precs
    in case d of
    IdApplDoc i aas@(hd : _) ->
        let p = Map.findWithDefault
              (if begPlace i || endPlace i then 0 else maxBound) i m in
        if isGenLiteral splitDoc ga i aas then Nothing else
        let lw = case getWeight ga hd of
                   Just (Weight _ _ l _) -> nextWeight ALeft ga i l
                   Nothing -> i
            rw = case getWeight ga $ last aas of
                   Just (Weight _ _ _ r) -> nextWeight ARight ga i r
                   Nothing -> i
            in Just $ Weight p i lw rw
    _ -> Nothing

isDiffAssoc :: AssocMap -> PrecedenceGraph -> Id -> Id -> Bool
isDiffAssoc assocs precs op arg =
    isInfix op && isInfix arg &&
           case precRel precs op arg of
               Lower -> False
               _ -> op /= arg || not (Map.member arg assocs)

isSafeLhs :: Id -> Id -> Bool
isSafeLhs op arg = isPostfix arg || endPlace op && not (isInfix arg)

isBoth :: PrecedenceGraph -> Id -> Id -> Bool
isBoth precs op arg = case precRel precs op arg of
                    BothDirections -> True
                    _ -> False

-- * the class stuff
class Pretty a where
    pretty :: a -> Doc

-- | change top-level to plain keywords
rmTopKey :: Doc -> Doc
rmTopKey = foldDoc idRecord
    { foldText = \ d k s -> case k of
          TopKey -> Text Keyword s
          _ -> d
    }

-- | add global annotations for proper mixfix printing
changeGlobalAnnos :: (GlobalAnnos -> GlobalAnnos) -> Doc -> Doc
changeGlobalAnnos = ChangeGlobalAnnos

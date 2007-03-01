{- |
Module      :  $Header$
Copyright   :  (c) Andy Gimblett and Uni Bremen 2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  a.m.gimblett@swansea.ac.uk
Stability   :  provisional
Portability :  portable

Printing abstract syntax of CSP-CASL

-}
module CspCASL.Print_CspCASL where

import CASL.ToDoc

import Common.Doc
import Common.DocUtils
import Common.Keywords (endS)

import CspCASL.AS_CspCASL
import CspCASL.AS_CspCASL_Process
import CspCASL.CspCASL_Keywords

instance Pretty BASIC_CSP_CASL_SPEC where
    pretty = printBasic_Csp_Casl_Spec

printBasic_Csp_Casl_Spec :: BASIC_CSP_CASL_SPEC -> Doc
printBasic_Csp_Casl_Spec (Basic_Csp_Casl_Spec d p) =
    keyword dataS <+> (pretty d) $+$
    keyword processS <+> (pretty p) $+$
    keyword endS

instance Pretty DATA_DEFN where
    pretty = printDataDefn

printDataDefn :: DATA_DEFN -> Doc
printDataDefn (Spec bs) = printBASIC_SPEC pretty pretty pretty bs 

instance Pretty PROCESS where
    pretty = printProcess

printProcess :: PROCESS -> Doc
printProcess  process = case process of
    Skip -> text "SKIP"
    Stop -> text "STOP"
    Div -> text "Div"
    Run es -> (text "Run") <+> (pretty es)
    Chaos es -> (text "Chaos") <+> (pretty es)
    PrefixProcess ev p ->
        (pretty ev) <+> (text "->") <+> (pretty p)
    InternalPrefixProcess v es p ->
        ((text "|~|") <+> (pretty v) <+>
         (text ":") <+> (pretty es) <+>
         (text "->") <+> (pretty p)
        )
    ExternalPrefixProcess v es p ->
        ((text "[]") <+> (pretty v) <+>
         (text ":") <+> (pretty es) <+>
         (text "->") <+> (pretty p)
        )
    Sequential p q ->
        (pretty p)  <+> (text ";") <+> (pretty q)
    ExternalChoice p q ->
        (pretty p) <+> (text "[]") <+> (pretty q)
    InternalChoice p q ->
        (pretty p) <+> (text "|~|") <+> (pretty q)
    Interleaving p q ->
        (pretty p) <+> (text "|||") <+> (pretty q)
    SynchronousParallel p q ->
        (pretty p) <+> (text "||") <+> (pretty q)
    GeneralisedParallel p es q ->
        ((pretty p) <+>
         (text "[|") <+> (pretty es) <+> (text "|]") <+>
         (pretty q)
        )
    AlphabetisedParallel p les res q ->
        ((pretty p) <+> (text "[") <+>
         (pretty les) <+> (text "||") <+> (pretty res) <+>
         (text "]") <+> (pretty q)
        )
    Hiding p es ->
        (pretty p) <+> (text "\\") <+> (pretty es)
    Renaming p r ->
        (pretty p) <+> (text "[[") <+> (pretty r) <+> (text "]]")
    ConditionalProcess f p q ->
        ((text "if") <+> (pretty f) <+>
         (text "then") <+> (pretty p) <+>
         (text "else") <+> (pretty q)
        )

instance Pretty EVENT where
    pretty = printEvent

printEvent :: EVENT -> Doc
printEvent (Event t) = pretty t

instance Pretty EVENT_SET where
    pretty = printEventSet

printEventSet :: EVENT_SET -> Doc
printEventSet (EventSet s) = pretty s

instance Pretty CSP_FORMULA where
    pretty = printCspFormula

printCspFormula :: CSP_FORMULA -> Doc
printCspFormula (Formula f) = pretty f

{- |
Module      :  $Header$
Copyright   :  (c) Andy Gimblett, Liam O'Reilly and Markus Roggenbach, Swansea University 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  csliam@swansea.ac.uk
Stability   :  provisional
Portability :  portable

Printing abstract syntax of Isabelle Proofs
-}

module Isabelle.IsaProofPrint where

import Common.Doc
import Common.DocUtils
import Isabelle.IsaConsts
import Isabelle.IsaProof


instance Pretty IsaProof where
    pretty = printIsaProof

printIsaProof :: IsaProof -> Doc
printIsaProof isaProof =
    (foldr1 ($+$) (map pretty p)) $+$ pretty e
        where p = proof isaProof
              e = end isaProof

instance Pretty ProofCommand where
    pretty = printProofCommand

printProofCommand :: ProofCommand -> Doc
printProofCommand pc =
    case pc of
      Apply pm -> text applyS  <+> parens(pretty pm)
      Back -> text backS
      Defer x -> text deferS <+> pretty x
      Prefer x -> text preferS <+> pretty x
      Refute -> text refuteS


instance Pretty ProofEnd where
    pretty = printProofEnd

printProofEnd :: ProofEnd -> Doc
printProofEnd pe =
    case pe of
      By pm -> text byS <+> parens(pretty pm)
      Done -> text doneS
      Oops -> text oopsS
      Sorry -> text sorryS


instance Pretty ProofMethod where
    pretty = printProofMethod

printProofMethod :: ProofMethod -> Doc
printProofMethod pm =
    case pm of
      Auto -> text autoS
      Simp -> text simpS
      Other s -> text s

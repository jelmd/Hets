{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, and Uni Bremen 2002-2003
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  non-portable (various -fglasgow-exts extensions)
 
   
   Provides data structures for logics (with symbols). Logics are
   a type class with an "identitiy" type (usually interpreted
   by a singleton set) which serves to treat logics as 
   data. All the functions in the type class take the
   identity as first argument in order to determine the logic.

   For logic (co)morphisms see Comorphism.hs

   References:

   J. A. Goguen and R. M. Burstall
   Institutions: Abstract Model Theory for Specification and
     Programming
   JACM 39, p. 95--146, 1992
   (general notion of logic - model theory only)

   J. Meseguer
   General Logics
   Logic Colloquium 87, p. 275--329, North Holland, 1989
   (general notion of logic - also proof theory;
    notion of logic representation, called map there)

   T. Mossakowski: 
   Specification in an arbitrary institution with symbols
   14th WADT 1999, LNCS 1827, p. 252--270
   (treatment of symbols and raw symbols, see also CASL semantics)

   T. Mossakowski, B. Klin:
   Institution Independent Static Analysis for CASL
   15h WADT 2001, LNCS 2267, p. 221-237, 2002.
   (what is needed for static anaylsis)

   S. Autexier and T. Mossakowski
   Integrating HOLCASL into the Development Graph Manager MAYA
   FroCoS 2002, to appear
   (interface to provers)

   Todo:
   ATerm, XML
   Weak amalgamability
   Metavars
   raw symbols are now symbols, symbols are now signature symbols
   provide both signature symbol set and symbol set of a signature
   
-}

module Logic.Logic where

import Common.Id
import Common.GlobalAnnotations
import Common.Lib.Set
import Common.Lib.Map
import Common.Lib.Graph
import Common.AnnoState
import Common.Result
import Common.AS_Annotation
import Logic.Prover -- for one half of class Sentences

import Common.PrettyPrint
import Data.Dynamic

-- for coercion used in Grothendieck.hs and Analysis modules

import UnsafeCoerce

-- for Conversion to ATerms 
import Common.ATerm.Lib -- (ATermConvertible)
import ATC.Graph
import ATC.AS_Annotation

-- diagrams are just graphs
type Diagram object morphism = Graph object morphism

-- | Amalgamability analysis might be undecidable, so we need
-- a special type for the result of ensures_amalgamability
data Amalgamates = Yes
		 | No String -- ^ the String contains the description of failure
		 | DontKnow 

-- languages, define like "data CASL = CASL deriving Show" 

class Show lid => Language lid where
    language_name :: lid -> String
    language_name i = show i

-- (a bit unsafe) coercion using the language name
coerce :: (Typeable a, Typeable b, Language lid1, Language lid2) => 
          lid1 -> lid2 -> a -> Maybe b
coerce i1 i2 a = if language_name i1 == language_name i2 then 
		 --fromDynamic (toDyn (a)) else Nothing
                 (Just $ unsafeCoerce a) else Nothing

rcoerce1 :: (Typeable a, Typeable b, Language lid1, Language lid2, Show a) => 
           lid1 -> lid2 -> Pos-> a -> b -> Result b
rcoerce1 i1 i2 pos a b = 
  maybeToResult pos 
                (if language_name i1 == language_name i2 then 
                   "Internal type error concerning types "++show (typeOf a)
                     ++" and "++show(typeOf b)
                  else "Logic "++ language_name i1 ++ " expected, but "
                         ++ language_name i2++" found")
                (coerce i1 i2 a)

rcoerce :: (Typeable a, Typeable b, Language lid1, Language lid2) => 
           lid1 -> lid2 -> Pos-> a -> Result b
rcoerce i1 i2 pos a = -- rcoerce1 i1 i2 pos a undefined
  maybeToResult pos 
                (if language_name i1 == language_name i2 then 
                   "Internal type error concerning type "++show (typeOf a)
                  else "Logic "++ language_name i1 ++ " expected, but "
                         ++ language_name i2++" found")
                (coerce i1 i2 a)

-- Categories are given by a quotient,
-- i.e. we need equality
-- Should we allow arbitrary composition graphs and build paths?

class (Language lid, Eq sign, Show sign, Eq morphism, Show morphism) => 
      Category lid sign morphism | lid -> sign, lid -> morphism where
         ide :: lid -> sign -> morphism
         comp :: lid -> morphism -> morphism -> Maybe morphism
           -- diagrammatic order
         dom, cod :: lid -> morphism -> sign
         legal_obj :: lid -> sign -> Bool
         legal_mor :: lid -> morphism -> Bool

-- abstract syntax, parsing and printing

class (Language lid, PrintLaTeX basic_spec, 
       PrintLaTeX symb_items, Eq symb_items,
       PrintLaTeX symb_map_items, Eq symb_map_items ,
       ATermConvertible basic_spec, 
       ATermConvertible symb_items, 
       ATermConvertible symb_map_items ) =>
      Syntax lid basic_spec symb_items symb_map_items
        | lid -> basic_spec, lid -> symb_items,
          lid -> symb_map_items
      where 
         -- parsing
         parse_basic_spec :: lid -> Maybe(AParser basic_spec)
         parse_symb_items :: lid -> Maybe(AParser symb_items)
         parse_symb_map_items :: lid -> Maybe(AParser symb_map_items)

         fromShATerm_basic_spec :: lid -> ATermTable -> basic_spec
	 fromShATerm_basic_spec _ att = fromShATerm att
         fromShATerm_symb_items :: lid -> ATermTable -> symb_items
         fromShATerm_symb_items _ att = fromShATerm att
         fromShATerm_symb_map_items :: lid -> ATermTable -> symb_map_items
         fromShATerm_symb_map_items _ att = fromShATerm att
	 fromShATerm_symb_items_list :: lid -> ATermTable -> [symb_items]
         fromShATerm_symb_items_list _ att = fromShATerm att
         fromShATerm_symb_map_items_list 
	     :: lid -> ATermTable -> [symb_map_items]
         fromShATerm_symb_map_items_list _ att = fromShATerm att
	 				      
-- sentences (plus prover stuff and "symbol" with "Ord" for efficient lookup)

class (Category lid sign morphism, Eq sentence, Show sentence, Ord sentence,
       PrettyPrint sentence, PrintLaTeX sign, PrintLaTeX morphism, 
       Ord symbol, Show symbol, PrintLaTeX symbol,
       ATermConvertible sentence, ATermConvertible symbol,
       ATermConvertible sign, ATermConvertible morphism,
       ATermConvertible proof_tree)
    => Sentences lid sentence proof_tree sign morphism symbol
        | lid -> sentence, lid -> sign, lid -> morphism,
          lid -> symbol, lid -> proof_tree
      where
         -- sentence translation
      map_sen :: lid -> morphism -> sentence -> Result sentence
         -- parsing of sentences
      parse_sentence :: lid -> Maybe (sign -> String -> Result sentence)
           -- is a term parser needed as well?
      sym_of :: lid -> sign -> Set symbol
      symmap_of :: lid -> morphism -> EndoMap symbol
      sym_name :: lid -> symbol -> Id 
      provers :: lid -> [Prover sign sentence proof_tree symbol]
      cons_checkers :: lid -> [Cons_checker 
			      (TheoryMorphism sign sentence morphism)] 
      fromShATerm_sentence :: lid -> ATermTable -> sentence
      fromShATerm_sentence _ att = fromShATerm att
      fromShATerm_symbol :: lid -> ATermTable -> symbol
      fromShATerm_symbol _ att = fromShATerm att
      fromShATerm_sign :: lid -> ATermTable -> sign
      fromShATerm_sign _ att = fromShATerm att
      fromShATerm_sign_list :: lid -> ATermTable -> [sign]
      fromShATerm_sign_list _ att = fromShATerm att
      fromShATerm_morphism :: lid -> ATermTable -> morphism
      fromShATerm_morphism _ att = fromShATerm att
      fromShATerm_proof_tree :: lid -> ATermTable -> proof_tree
      fromShATerm_proof_tree _ att = fromShATerm att
      fromShATerm_l_sentence_list :: lid -> ATermTable -> [Named sentence]
      fromShATerm_l_sentence_list _ att = fromShATerm att
      fromShATerm_diagram :: lid -> ATermTable -> Diagram sign morphism
      fromShATerm_diagram _ att = fromShATerm att

-- static analysis

class ( Syntax lid basic_spec symb_items symb_map_items
      , Sentences lid sentence proof_tree sign morphism symbol
      , Show raw_symbol, Eq raw_symbol, Ord raw_symbol, PrintLaTeX raw_symbol)
    => StaticAnalysis lid 
        basic_spec sentence proof_tree symb_items symb_map_items
        sign morphism symbol raw_symbol 
        | lid -> basic_spec, lid -> sentence, lid -> symb_items,
          lid -> symb_map_items, lid -> proof_tree,
          lid -> sign, lid -> morphism, lid -> symbol, lid -> raw_symbol
      where
         -- static analysis of basic specifications and symbol maps
         basic_analysis :: lid -> 
                           Maybe((basic_spec,  -- abstract syntax tree
                            sign,   -- efficient table for env signature
                            GlobalAnnos) ->   -- global annotations
                           Result (basic_spec,sign,sign,[Named sentence]))
                           -- the resulting bspec has analyzed axioms in it
                           -- the first output sign united with the input sign
                           -- should yield the second output sign
                           -- the second output sign is the accumulated sign
         -- Shouldn't the following deliver Maybes???
         sign_to_basic_spec :: lid -> sign -> [Named sentence] -> basic_spec
         stat_symb_map_items :: 
	     lid -> [symb_map_items] -> Result (EndoMap raw_symbol)
         stat_symb_items :: lid -> [symb_items] -> Result [raw_symbol] 
         -- architectural sharing analysis
         ensures_amalgamability :: lid ->
              (Diagram sign morphism, [LEdge morphism]) -> Result Amalgamates

         -- symbols and symbol maps
         symbol_to_raw :: lid -> symbol -> raw_symbol
         id_to_raw :: lid -> Id -> raw_symbol 
         matches :: lid -> symbol -> raw_symbol -> Bool
   
         -- operations on signatures and morphisms
         empty_signature :: lid -> sign
         signature_union :: lid -> sign -> sign -> Result sign
         morphism_union :: lid -> morphism -> morphism -> Result morphism
         final_union :: lid -> sign -> sign -> Result sign
           -- see CASL reference manual, III.4.1.2
         is_subsig :: lid -> sign -> sign -> Bool
         inclusion :: lid -> sign -> sign -> Result morphism
         generated_sign, cogenerated_sign :: 
	     lid -> Set symbol -> sign -> Result morphism
         induced_from_morphism :: 
	     lid -> EndoMap raw_symbol -> sign -> Result morphism
         induced_from_to_morphism :: 
	     lid -> EndoMap raw_symbol -> sign -> sign -> Result morphism 

-- sublogics

class (Eq l, Show l) => LatticeWithTop l where
  meet, join :: l -> l -> l
  top :: l

(<<=) :: LatticeWithTop l => l -> l -> Bool
a <<= b = meet a b == b 

-- a dummy instance 
instance LatticeWithTop () where
  meet _ _ = ()
  join _ _ = ()
  top = ()

-- logics

class (StaticAnalysis lid 
        basic_spec sentence proof_tree symb_items symb_map_items
        sign morphism symbol raw_symbol,
       LatticeWithTop sublogics,ATermConvertible sublogics,
       Typeable sublogics, Typeable basic_spec, Typeable sentence, 
       Typeable symb_items, Typeable symb_map_items, Typeable sign, 
       Typeable morphism, Typeable symbol, Typeable raw_symbol, 
       Typeable proof_tree) =>
      Logic lid sublogics
        basic_spec sentence symb_items symb_map_items
        sign morphism symbol raw_symbol proof_tree
        | lid -> sublogics, lid -> basic_spec, lid -> sentence, 
          lid -> symb_items, lid -> symb_map_items, lid -> proof_tree,
          lid -> sign, lid -> morphism, lid ->symbol, lid -> raw_symbol
	  where

         data_logic :: lid -> Maybe AnyLogic
	 data_logic _ = Nothing

         sublogic_names :: lid -> sublogics -> [String] 
	 sublogic_names _ _ = []
             -- the first name is the principal name
         all_sublogics :: lid -> [sublogics]
	 all_sublogics _ = []

         is_in_basic_spec :: lid -> sublogics -> basic_spec -> Bool
         is_in_basic_spec _ _ _ = False
         is_in_sentence :: lid -> sublogics -> sentence -> Bool
         is_in_sentence _ _ _ = False
         is_in_symb_items :: lid -> sublogics -> symb_items -> Bool
         is_in_symb_items _ _ _ = False
	 is_in_symb_map_items :: lid -> sublogics -> symb_map_items -> Bool
         is_in_symb_map_items _ _ _ = False
         is_in_sign :: lid -> sublogics -> sign -> Bool
         is_in_sign _ _ _ = False
	 is_in_morphism :: lid -> sublogics -> morphism -> Bool
         is_in_morphism _ _ _ = False
         is_in_symbol :: lid -> sublogics -> symbol -> Bool
	 is_in_symbol _ _ _ = False
 
         min_sublogic_basic_spec :: lid -> basic_spec -> sublogics
         min_sublogic_sentence :: lid -> sentence -> sublogics
         min_sublogic_symb_items :: lid -> symb_items -> sublogics
         min_sublogic_symb_map_items :: lid -> symb_map_items -> sublogics
         min_sublogic_sign :: lid -> sign -> sublogics
         min_sublogic_morphism :: lid -> morphism -> sublogics
         min_sublogic_symbol :: lid -> symbol -> sublogics

         proj_sublogic_basic_spec :: lid -> sublogics 
				  -> basic_spec -> basic_spec
	 proj_sublogic_basic_spec _ _ b = b			     
         proj_sublogic_symb_items :: lid -> sublogics 
				  -> symb_items -> Maybe symb_items
	 proj_sublogic_symb_items _ _ _ = Nothing
         proj_sublogic_symb_map_items :: lid -> sublogics 
				      -> symb_map_items -> Maybe symb_map_items
	 proj_sublogic_symb_map_items _ _ _ = Nothing
         proj_sublogic_sign :: lid -> sublogics -> sign -> sign 
         proj_sublogic_sign _ _ s = s
	 proj_sublogic_morphism :: lid -> sublogics -> morphism -> morphism
         proj_sublogic_morphism _ _ m = m
	 proj_sublogic_epsilon :: lid -> sublogics -> sign -> morphism
	 proj_sublogic_epsilon li _ s = ide li s
         proj_sublogic_symbol :: lid -> sublogics -> symbol -> Maybe symbol
	 proj_sublogic_symbol _ _ _ = Nothing
         fromShATerm_sublogics :: lid -> ATermTable -> sublogics
         fromShATerm_sublogics _ att = fromShATerm att
 
----------------------------------------------------------------
-- Existential type covering any logic
----------------------------------------------------------------

data AnyLogic = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
        sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree =>
        Logic lid

instance Show AnyLogic where
  show (Logic lid) = language_name lid
instance Eq AnyLogic where
  Logic lid1 == Logic lid2 = language_name lid1 == language_name lid2

----------------------------------------------------------------
-- Typeable instances
----------------------------------------------------------------

namedTc :: TyCon
namedTc = mkTyCon "Common.AS_Annotation.Named"

instance Typeable s => Typeable (Named s) where 
  typeOf s = mkAppTy namedTc [typeOf ((undefined :: Named a -> a) s)]

setTc :: TyCon
setTc = mkTyCon "Common.Lib.Set.Set"

instance Typeable a => Typeable (Set a) where
  typeOf s = mkAppTy setTc [typeOf ((undefined:: Set a -> a) s)]

mapTc :: TyCon
mapTc = mkTyCon "Common.Lib.Map.Map"

instance (Typeable a, Typeable b) => Typeable (Map a b) where
  typeOf m = mkAppTy mapTc [typeOf ((undefined :: Map a b -> a) m),
                            typeOf ((undefined :: Map a b -> b) m)]

{- class hierarchy:
                            Language
               __________/     
   Category
      |                  /       
   Sentences      Syntax
      \            /
      StaticAnalysis (no sublogics)
            \                        
             \                             
            Logic

-}

-- needs ghc -fglasgow-exts 

{- HetCATS/Grothendieck.hs
   $Id$
   Till Mossakowski
   
   The Grothendieck logic is defined to be the
   heterogeneous logic over the logic graph.
   This will be the logic over which the data 
   structures and algorithms for specification in-the-large
   are built.

   References:

   R. Diaconescu:
   Grothendieck institutions
   J. applied categorical structures, to appear

   T. Mossakowski: 
   Heterogeneous development graphs and heterogeneous borrowing
   Fossacs 2002, LNCS 2303

   T. Mossakowski: Simplified heterogeneous specification
   Submitted

   Todo:

-}

module Grothendieck where

import Logic
import LogicGraph
import qualified Dynamic

data Grothendieck = Grothendieck

data G_basic_spec = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_basic_spec id basic_spec

data G_sentence = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_sentence id sentence

data G_anno = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_anno id anno

data G_sign = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_sign id sign

data G_morphism = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_morphism id morphism

data G_symbol = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_symbol id symbol

data G_symb_items = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_symb_items id symb_items

data G_symb_items_list = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_symb_items_list id [symb_items]

data G_symb_map_items = forall id
        basic_spec sentence symb_items symb_map_items anno
        local_env sign morphism symbol raw_symbol .
        Logic id
         basic_spec sentence symb_items symb_map_items anno
         local_env sign morphism symbol raw_symbol =>
        G_symb_map_items id symb_map_items

homogenize_symb_items :: [G_symb_items] -> Maybe G_symb_items_list
homogenize_symb_items [] = Nothing
homogenize_symb_items (G_symb_items i (s::symb_map_items) : rest) = 
  maybe Nothing 
        (\l -> Just (G_symb_items_list i l))  
        ( sequence (map (\(G_symb_items _ si) -> 
            (Dynamic.fromDynamic (Dynamic.toDyn si))::Maybe symb_map_items) rest) )


{- HetCATS/HasCASL/PrintAs.hs
   $Id$
   Authors: Christian Maeder
   Year:    2002
   
   printing As data types
-}

module PrintAs where

import As
import Keywords
import HToken
import Pretty
import PrettyPrint
import GlobalAnnotations(GlobalAnnos)
import Print_AS_Annotation

commas, semis :: PrettyPrint a => GlobalAnnos -> [a] -> Doc
commas ga l = fsep $ punctuate comma (map (printText0 ga) l)
semis ga l = sep $ punctuate semi (map (printText0 ga) l)

instance PrettyPrint TypePattern where 
    printText0 ga (TypePattern name args _) = printText0 ga name
				 <> fcat (map (parens . printText0 ga) args)
    printText0 ga (TypePatternToken t) = printText0 ga t
    printText0 ga (MixfixTypePattern ts) = fsep (map (printText0 ga) ts)
    printText0 ga (BracketTypePattern k l _) = bracket k $ commas ga l
    printText0 ga (TypePatternArgs l) = semis ga l

bracket :: BracketKind -> Doc -> Doc
bracket Parens t = parens t
bracket Squares t = Pretty.brackets t
bracket Braces t = braces t

instance PrettyPrint Type where 
    printText0 ga (TypeConstrAppl name kind args _) = printText0 ga name 
			  <> (case kind of 
			       Kind [] (Universe _) _ -> empty
			       _ -> space <> colon <> printText0 ga kind)
			  <> if null args then empty 
			     else parens (commas ga args)
    printText0 ga (TypeToken t) = printText0 ga t
    printText0 ga (BracketType k l _) = bracket k $ commas ga l
    printText0 ga (KindedType t kind _) = printText0 ga t  
			  <> (case kind of 
			       Kind [] (Universe _) _ -> empty
			       _ -> space <> colon <> printText0 ga kind)
    printText0 ga (MixfixType ts) = fsep (map (printText0 ga) ts)
    printText0 ga (TupleType args _) = parens $ commas ga args
    printText0 ga (LazyType t _) = text quMark <+> printText0 ga (t)  
    printText0 ga (ProductType ts _) = fsep (punctuate (space <> text timesS) 
					 (map (printText0 ga) ts))
    printText0 ga (FunType t1 arr t2 _) = printText0 ga t1
				      <+> printText0 ga arr
				      <+> printText0 ga t2

-- no curried notation for bound variables 
instance PrettyPrint TypeScheme where
    printText0 ga (SimpleTypeScheme t) = printText0 ga t
    printText0 ga (TypeScheme vs t _) = text forallS
				   <+> semis ga vs 
				   <+> text dotS
				   <+> printText0 ga t

instance PrettyPrint Partiality where
    printText0 _ Partial = text quMark
    printText0 _ Total = text exMark

instance PrettyPrint Arrow where 
    printText0 _ FunArr = text funS
    printText0 _ PFunArr = text pFun
    printText0 _ ContFunArr = text contFun
    printText0 _ PContFunArr = text pContFun 


instance PrettyPrint Quantifier where 
    printText0 _ Universal = text forallS
    printText0 _ Existential = text existsS 
    printText0 _ Unique = text $ existsS ++ exMark

instance PrettyPrint TypeQual where 
    printText0 _ OfType = colon
    printText0 _ AsType = text asS
    printText0 _ InType = text inS

instance PrettyPrint LogOp where
    printText0 _ NotOp = text notS
    printText0 _ AndOp = text lAnd
    printText0 _ OrOp = text lOr
    printText0 _ ImplOp = text implS
    printText0 _ EquivOp = text equivS

instance PrettyPrint EqOp where
    printText0 _ EqualOp = text equalS
    printText0 _ ExEqualOp = text exEqual

instance PrettyPrint Formula where
    printText0 ga (TermFormula t) = printText0 ga t
    printText0 ga (ConnectFormula o fs _) = parens $
	fsep (punctuate (space <> printText0 ga o) (map (printText0 ga) fs))
    printText0 ga (EqFormula o t1 t2 _) = printText0 ga t1
					  <+> printText0 ga o
					  <+> printText0 ga t2
    printText0 ga (DefFormula t _) = text defS <+> printText0 ga t
    printText0 ga (QuantifiedFormula q vs f _) =
	printText0 ga q <+> semis ga vs <+> text dotS <+> printText0 ga f
    printText0 ga (PolyFormula ts f _) = 
	text forallS <+> semis ga ts <+> text dotS <+> printText0 ga f

instance PrettyPrint Term where
    printText0 ga (CondTerm t1 f t2 _) =  printText0 ga t1
				      <+> text whenS
				      <+> printText0 ga f
				      <+> text elseS
				      <+> printText0 ga t2
    printText0 ga (QualVar v t _) = parens $ text varS
			<+> printText0 ga v
			<+> colon
			<+> printText0 ga t
    printText0 ga (QualOp n t _) = parens $
			text opS 
			<+> printText0 ga n
			<+> colon
			<+> printText0 ga t
    printText0 ga (ApplTerm t1 t2 _) = printText0 ga t1
			<+> parens (printText0 ga t2)
    printText0 ga (TupleTerm ts _) = parens $ commas ga ts 
    printText0 ga (TypedTerm term q typ _) = printText0 ga term
			  <+> printText0 ga q
			  <+> printText0 ga typ
    printText0 ga (QuantifiedTerm q vs t _) = printText0 ga q
					  <+> semis ga vs 
					  <+> text dotS    
					  <+> printText0 ga t
    printText0 ga (LambdaTerm ps q t _) = text lamS
				      <+> (if length ps == 1 then 
					     printText0 ga $ head ps
					     else fcat $ map 
					   (parens.printText0 ga) ps)
				      <+> (case q of 
					   Partial -> text dotS
					   Total -> text $ dotS ++ exMark)
				      <+> printText0 ga t
    printText0 ga (CaseTerm t es _ ) = text caseS
				   <+> printText0 ga t
				   <+> text ofS
				   <+> vcat (punctuate (text " | ")
					     (map (printEq0 ga funS) es))
    printText0 ga (LetTerm es t _) =  text letS
				   <+> vcat (punctuate semi
					     (map (printEq0 ga equalS) es))
				   <+> text inS
				   <+> printText0 ga t
    printText0 ga (TermToken t) = printText0 ga t
    printText0 ga (MixfixTerm ts) = fsep $ map (printText0 ga) ts
    printText0 ga (BracketTerm k l _) = bracket k $ commas ga l

instance PrettyPrint Pattern where 
    printText0 ga (PatternVars vs _) = semis ga vs
    printText0 ga (PatternConstr n t args _) = printText0 ga n 
			  <+> colon
			  <+> printText0 ga t 
			  <+> fcat (map (parens.printText0 ga) args)
    printText0 ga (PatternToken t) = printText0 ga t
    printText0 ga (BracketPattern  k l _) = bracket k $ commas ga l
    printText0 ga (TuplePattern ps _) = parens $ commas ga ps
    printText0 ga (MixfixPattern ps) = fsep (map (printText0 ga) ps)
    printText0 ga (TypedPattern p t _) = printText0 ga p 
			  <+> colon
			  <+> printText0 ga t 
    printText0 ga (AsPattern v p _) = printText0 ga v
			  <+> text asP
			  <+> printText0 ga p


printEq0 :: GlobalAnnos -> String -> ProgEq -> Doc
printEq0 ga s (ProgEq p t _) = fsep [printText0 ga p 
			  , text s
			  , printText0 ga t] 

instance PrettyPrint VarDecl where 
    printText0 ga (VarDecl v t _ _) = printText0 ga v <+> colon
						 <+> printText0 ga t

instance PrettyPrint TypeVarDecl where 
    printText0 ga (TypeVarDecl v c _ _) = printText0 ga v <+> 
					      case c of 
					      Downset t -> 
					        text lessS <+> printText0 ga t
					      _ -> colon <+> printText0 ga c

instance PrettyPrint GenVarDecl where 
    printText0 ga (GenVarDecl v) = printText0 ga v
    printText0 ga (GenTypeVarDecl tv) = printText0 ga tv

instance PrettyPrint TypeArg where 
    printText0 ga (TypeArg v c _ _) = printText0 ga v <> colon 
				      <> printText0 ga c

instance PrettyPrint Variance where 
    printText0 _ CoVar = text plusS
    printText0 _ ContraVar = text minusS
    printText0 _ InVar = empty

instance PrettyPrint ExtClass where 
    printText0 ga (ExtClass c v _) = printText0 ga c <> printText0 ga v 
				     <> space

instance PrettyPrint ProdClass where 
    printText0 ga (ProdClass l _) = fcat $ punctuate (text timesS) 
			       (map (printText0 ga) l)

instance PrettyPrint Kind where 
    printText0 ga (Kind l c _) = (if null l then empty else 
			      (fcat $ punctuate (text funS) 
			       (map (printText0 ga) l))
			      <> text funS) 
			     <> printText0 ga c

instance PrettyPrint Class where 
    printText0 _ (Universe _) = empty
    printText0 ga (ClassName n) = printText0 ga n
    printText0 ga (Downset t) = braces $ text lessS <+> printText0 ga t
    printText0 ga (Intersection c _) = parens $ commas ga c 

instance PrettyPrint Types where
    printText0 ga (Types l _) = Pretty.brackets $ commas ga l

instance PrettyPrint InstOpName where
    printText0 ga (InstOpName n l) = printText0 ga n 
				     <> fcat(map (printText0 ga) l)

------------------------------------------------------------------------
-- item stuff
------------------------------------------------------------------------
instance PrettyPrint PseudoType where 
    printText0 ga (SimplePseudoType t) = printText0 ga t
    printText0 ga (PseudoType l t _) = text lamS 
				<+> fcat(map (printText0 ga) l)
				<+> text dotS <+> printText0 ga t

instance PrettyPrint TypeArgs where
    printText0 ga (TypeArgs l _) = semis ga l

instance PrettyPrint TypeVarDecls where 
    printText0 ga (TypeVarDecls l _) = Pretty.brackets $ semis ga l

instance PrettyPrint BasicSpec where 
    printText0 ga (BasicSpec l) = vcat (map (printText0 ga) l)

instance PrettyPrint ProgEq where
    printText0 ga = printEq0 ga equalS

instance PrettyPrint BasicItem where 
    printText0 ga (SigItems s) = printText0 ga s
    printText0 ga (ProgItems l _) = text programS <+> semis ga l
    printText0 ga (ClassItems i l _) = text classS <+> printText0 ga i
			       <+> semis ga l
    printText0 ga (GenVarItems l _) = text varS <+> semis ga l
    printText0 ga (FreeDatatype l _) = text freeS <+> text typeS 
				    <+> semis ga l
    printText0 ga (GenItems l _) = text generatedS <+> braces (semis ga l)
    printText0 ga (AxiomItems vs fs _) = (if null vs then empty
			       else text forallS <+> semis ga vs)
			       $$ vcat (map 
					 (\x -> text dotS <+> printText0 ga x) 
					 fs)

instance PrettyPrint SigItems where 
    printText0 ga (TypeItems i l _) = text typeS <+> printText0 ga i 
				      <+> semis ga l
    printText0 ga (OpItems l _) = text opS <+> semis ga l
    printText0 ga (PredItems l _) = text predS <+> semis ga l

instance PrettyPrint Instance where
    printText0 _ Instance = text instanceS
    printText0 _ _ = empty
		      
instance PrettyPrint ClassItem where 
    printText0 ga (ClassItem d l _) = printText0 ga d $$ 
				   if null l then empty 
				      else braces (semis ga l)

instance PrettyPrint ClassDecl where 
    printText0 ga (ClassDecl l _) = commas ga l
    printText0 ga (SubclassDecl l s _) = commas ga l <> text lessS 
					 <> printText0 ga s
    printText0 ga (ClassDefn n c _) =  printText0 ga n 
			       <> text equalS 
			       <> printText0 ga c
    printText0 ga (DownsetDefn c v t _) = printText0 ga c
			       <> text equalS 
			       <> braces (printText0 ga v 
					   <> text dotS
					   <> printText0 ga v 
					   <> (text lessS
					       <+> printText0 ga t))

instance PrettyPrint TypeItem where 
    printText0 ga (TypeDecl l k _) = commas ga l <> 
				  case k of 
				  Kind [] (Universe _) _ -> empty
				  _ -> space <> colon <> printText0 ga k
    printText0 ga (SubtypeDecl l t _) = commas ga l <+> text lessS 
					<+> printText0 ga t
    printText0 ga (IsoDecl l _) = cat(punctuate (text " = ") 
				      (map (printText0 ga) l))
    printText0 ga (SubtypeDefn p v t f _) = printText0 ga p
			       <+> text equalS 
			       <+> braces (printText0 ga v 
					   <+> colon
					   <+> printText0 ga t 
					   <+> text dotS
					   <+> printText0 ga f)
    printText0 ga (AliasType p k t _) =  (printText0 ga p <>
				       case k of 
				       Kind [] (Universe _) _ -> empty
				       _ -> space <> colon <> printText0 ga k)
				       <+> text assignS
				       <+> printText0 ga t
    printText0 ga (Datatype t) = printText0 ga t

instance PrettyPrint OpItem where 
    printText0 ga (OpDecl l t as _) = commas ga l <+> colon
				   <+> (printText0 ga t
					<> (if null as then empty else comma)
					<> commas ga as)
    printText0 ga (OpDefn n ps s p t _) = (printText0 ga n 
					<> fcat (map (printText0 ga) ps))
			    <+> (colon <> if p == Partial 
				 then text quMark else empty)
 			    <+> printText0 ga s 
			    <+> text equalS
			    <+> printText0 ga t

instance PrettyPrint PredItem where 
    printText0 ga (PredDecl l t _) = commas ga l <+> colon <+> printText0 ga t
    printText0 ga (PredDefn n ps f _) = (printText0 ga n 
					 <> fcat (map (printText0 ga) ps))
				     <+> text equivS
				     <+> printText0 ga f

instance PrettyPrint BinOpAttr where 
    printText0 _ Assoc = text assocS
    printText0 _ Comm = text commS
    printText0 _ Idem = text idemS

instance PrettyPrint OpAttr where 
    printText0 ga (BinOpAttr a _) = printText0 ga a
    printText0 ga (UnitOpAttr t _) = text unitS <+> printText0 ga t

instance PrettyPrint DatatypeDecl where 
    printText0 ga (DatatypeDecl p k as d _) = (printText0 ga p <>
				       case k of 
				       Kind [] (Universe _) _ -> empty
				       _ -> space <> colon <> printText0 ga k)
				  <+> text defnS
				  <+> vcat(punctuate (text " | ") 
					   (map (printText0 ga) as))
				  <+> case d of { Nothing -> empty
						; Just c -> text derivingS
						  <+> printText0 ga c
						}

instance PrettyPrint Alternative where 
    printText0 ga (Constructor n cs p _) = printText0 ga n 
					<> fcat (map (printText0 ga) cs)
					<> (case p of {Partial -> text quMark;
						       _ -> empty})
    printText0 ga (Subtype l _) = text typeS <+> commas ga l

instance PrettyPrint Components where 
    printText0 ga (Selector n p t _ _) = printText0 ga n 
				<> colon <> (case p of { Partial ->text quMark;
							 _ -> empty } 
					      <+> printText0 ga t)
    printText0 ga (NoSelector t) = printText0 ga t
    printText0 ga (NestedComponents l _) = parens $ semis ga l

instance PrettyPrint OpName where 
    printText0 ga (OpName n ts) = printText0 ga n 
				  <+> fcat(map (printText0 ga) ts)


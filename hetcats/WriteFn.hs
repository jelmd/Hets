
{---
  HetCATS/hetcats/WriteFn.hs
  @version $Id$
  @author Klaus L&uuml;ttich<BR>
  Year:   2002
  <p>
  This module provides functions to write a pretty printed abstract
  syntax and all the other formats.
  </p>
-}
module WriteFn where

import Options
-- import List
import Utils

import IO 
import IOExts (trace)
import Print_HetCASL
import AS_Library (LIB_DEFN()) 
import GlobalLibraryAnnotations

-- for debugging

{---
  Write the given LIB_DEFN in every format that HetcatsOpts includes.
  Filenames are determined by the output formats.
  @param opt - Options Either default or given on the comandline
  @param ld  - a LIB_DEFN read as ATerm or parsed
-}
write_LIB_DEFN :: HetcatsOpts -> LIB_DEFN -> IO ()
write_LIB_DEFN opt ld = sequence_ $ map write_type $ outtypes opt
    where write_type :: OutType -> IO ()
	  write_type t = 
	      case t of 
	      HetCASLOut Ascii -> 
		  write_casl_asc (verbose opt) (casl_asc_filename opt) ld
	      HetCASLOut Latex ->
		  write_casl_latex (verbose opt) (casl_latex_filename opt) ld
	      _ -> trace ( "the outtype \"" ++ 
		           show t ++ "\" is not implemented")
		         (return ())
{---
  Produces the filename of the pretty printed CASL-file.
  @param opt   - Options from the command line 
  @return path - full path to the generated file
-}
casl_asc_filename :: HetcatsOpts -> FilePath
casl_asc_filename opt =
    let (base,_,_) = fileparse [".casl",".tree.gen_trm"] (infile opt)
    in (outdir opt) ++ "/" ++ base ++ ".pp.casl"
      -- maybe an optin out-file is better

write_casl_asc :: Int -> FilePath -> LIB_DEFN -> IO ()
write_casl_asc verb oup ld =
    do hout <- openFile oup WriteMode
       if verb > 3 then putStrLn $ show (initGlobalAnnos ld)
        else return ()
       hPutStr hout $ printLIB_DEFN_text ld

casl_latex_filename :: HetcatsOpts -> FilePath
casl_latex_filename opt =
    let (base,_,_) = fileparse [".casl",".tree.gen_trm"] (infile opt)
    in (outdir opt) ++ "/" ++ base ++ ".pp.tex"
      -- maybe an optin out-file is better

write_casl_latex :: Int -> FilePath -> LIB_DEFN -> IO ()
write_casl_latex verb oup ld =
    do hout <- openFile oup WriteMode
       if verb > 3 then putStrLn $ show (initGlobalAnnos ld)
        else return ()
       hPutStr hout $ printLIB_DEFN_latex ld


{- | 
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2004
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  portable

Description :  utilites for tracing

-}

module Common.Trace where

import Debug.Trace

strace :: Show a => String -> a -> a
strace s x = trace (s++": "++show x) x

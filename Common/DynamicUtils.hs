{-# OPTIONS -cpp #-}
{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (does -cpp on __GLASGOW_HASKELL__)

Description :  utils for creating instances of Dynamic.Typeable

mkAppTy was renamed to mkTyConApp in ghc version 6.3 upwards
-}

module Common.DynamicUtils ( mkTyConApp, mkTyCon, TyCon, TypeRep, Typeable(..)
                           , Dynamic, toDyn, fromDyn) where

import Data.Dynamic
#if __GLASGOW_HASKELL__<=602
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Data.Ratio

mkTyConApp :: TyCon -> [TypeRep] -> TypeRep
mkTyConApp = mkAppTy

setTc :: TyCon
setTc = mkTyCon "Common.Lib.Set.Set"

instance Typeable a => Typeable (Set.Set a) where
  typeOf s = mkTyConApp setTc [typeOf ((error "Common.DynamicUtils":: Set.Set a -> a) s)]

mapTc :: TyCon
mapTc = mkTyCon "Common.Lib.Map.Map"

instance (Typeable a, Typeable b) => Typeable (Map.Map a b) where
  typeOf m = mkTyConApp mapTc [typeOf ((error "Common.DynamicUtils" :: Map.Map a b -> a) m),
                            typeOf ((error "Common.DynamicUtils" :: Map.Map a b -> b) m)]
#endif
#if __GLASGOW_HASKELL__<=504
ratioTc :: TyCon
ratioTc = mkTyCon "Data.Ratio"

instance Typeable a => Typeable (Ratio a) where
  typeOf s = mkTyConApp ratioTc [typeOf ((error "Common.DynamicUtils":: Ratio a -> a) s)]
#endif

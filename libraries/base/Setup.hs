{-# LANGUAGE CPP #-}
-- Otherwise it tries to include Prelude from *this* base
{-# LANGUAGE NoImplicitPrelude, PackageImports #-}
module Main (main) where

import "base" Prelude

import Distribution.Simple

main :: IO ()
#ifdef ghcjs_HOST_OS
main = defaultMain
#else
main = defaultMainWithHooks autoconfUserHooks
#endif

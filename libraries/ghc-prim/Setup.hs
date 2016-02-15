
-- We need to do some ugly hacks here because of GHC magic

module Main (main) where

import Control.Monad
import Data.List
import Data.Maybe
import Distribution.ModuleName (components)
import Distribution.PackageDescription
import Distribution.Simple
import Distribution.Simple.LocalBuildInfo
import Distribution.Simple.Program
import Distribution.Simple.Utils
import Distribution.Simple.Setup
import Distribution.Simple.Register
import Distribution.Simple.Install
import Distribution.Text
import System.Cmd
import System.FilePath
import System.Exit
import System.Directory

import qualified Data.ByteString               as B
import qualified Distribution.Compat.Exception as E

main :: IO ()
main = do let hooks = simpleUserHooks {
                  regHook = addPrimModule
                          $ regHook simpleUserHooks,
                  instHook = myInstHook,
                  buildHook = build_primitive_sources
                            $ buildHook simpleUserHooks,
                  haddockHook = addPrimModuleForHaddock
                              $ build_primitive_sources
                              $ haddockHook simpleUserHooks }
          defaultMainWithHooks hooks

type Hook a = PackageDescription -> LocalBuildInfo -> UserHooks -> a -> IO ()

addPrimModule :: Hook a -> Hook a
addPrimModule f pd lbi uhs x =
    do let -- I'm not sure which one of these we actually need to change.
           -- It seems bad that there are two.
           pd' = addPrimModuleToPD pd
           lpd = addPrimModuleToPD (localPkgDescr lbi)
           lbi' = lbi { localPkgDescr = lpd }
       f pd' lbi' uhs x

addPrimModuleForHaddock :: Hook a -> Hook a
addPrimModuleForHaddock f pd lbi uhs x =
    do let pc = withPrograms lbi
           pc' = userSpecifyArgs "haddock" ["GHC/Prim.hs"] pc
           lbi' = lbi { withPrograms = pc' }
       f pd lbi' uhs x

addPrimModuleToPD :: PackageDescription -> PackageDescription
addPrimModuleToPD pd =
    case library pd of
    Just lib ->
        let ems = fromJust (simpleParse "GHC.Prim") : exposedModules lib
            lib' = lib { exposedModules = ems }
        in pd { library = Just lib' }
    Nothing ->
        error "Expected a library, but none found"

build_primitive_sources :: Hook a -> Hook a
build_primitive_sources f pd lbi uhs x
 = do when (compilerFlavor (compiler lbi) == GHC ||
            compilerFlavor (compiler lbi) == GHCJS) $ do
          let genprimopcode = "genprimopcode"
              runGenprimopcode options tmp out = do
                writeFile tmp "{-# LANGUAGE CPP #-}\n#ifdef ghcjs_HOST_OS\n"
                maybeExit $ system (genprimopcode ++ options ++ " < " ++ primops ++ " >> " ++ tmp)
                appendFile tmp "\n#else\n"
                maybeExit $ system (genprimopcode ++ options ++ " < " ++ primops_native ++ " >> " ++ tmp)
                appendFile tmp "\n#endif\n"
                maybeUpdateFile tmp out
              primops = joinPath ["..", "..", "data", "primops-js.txt"]
              primops_native = joinPath ["..", "..", "data", "primops-native.txt"]
              primhs = joinPath ["GHC", "Prim.hs"]
              primopwrappers = joinPath ["GHC", "PrimopWrappers.hs"]
              primhs_tmp = addExtension primhs "tmp"
              primopwrappers_tmp = addExtension primopwrappers "tmp"
          runGenprimopcode " --make-haskell-source"   primhs_tmp primhs
          runGenprimopcode " --make-haskell-wrappers" primopwrappers_tmp primopwrappers
      f pd lbi uhs x

-- Replace a file only if the new version is different from the old.
-- This prevents make from doing unnecessary work after we run 'setup makefile'
maybeUpdateFile :: FilePath -> FilePath -> IO ()
maybeUpdateFile source target = do
  let readf file = fmap (either (const Nothing) Just) (E.tryIO $ B.readFile file)
  s <- readf source
  t <- readf  target
  if isJust s && s == t
    then removeFile source
    else do doesFileExist target >>= flip when (removeFile target)
            renameFile source target

myInstHook :: PackageDescription -> LocalBuildInfo
                   -> UserHooks -> InstallFlags -> IO ()
myInstHook pkg_descr localbuildinfo uh flags = do
  let copyFlags = defaultCopyFlags {
                      copyDistPref   = installDistPref flags,
                      copyDest       = toFlag NoCopyDest,
                      copyVerbosity  = installVerbosity flags
                  }
  install pkg_descr localbuildinfo copyFlags
  let registerFlags = defaultRegisterFlags {
                          regDistPref  = installDistPref flags,
                          regInPlace   = installInPlace flags,
                          regPackageDB = installPackageDB flags,
                          regVerbosity = installVerbosity flags
                      }
  when (hasLibs pkg_descr) $ addPrimModule (\pd lbi _ -> register pd lbi)
     pkg_descr localbuildinfo uh registerFlags



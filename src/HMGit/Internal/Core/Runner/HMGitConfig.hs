{-# LANGUAGE TemplateHaskell #-}
module HMGit.Internal.Core.Runner.HMGitConfig (
    HMGitConfig (..)
  , hmGitConfig
) where

import           HMGit.Internal.Exceptions (noSuchThing)

import           Control.Exception.Safe    (MonadThrow, throw)
import           Control.Monad.Extra       (andM, ifM)
import           Control.Monad.Fix         (fix)
import           Control.Monad.IO.Class    (MonadIO (..))
import           Path                      (Dir, Rel)
import qualified Path                      as P
import qualified Path.IO                   as P
import           Text.Printf               (printf)

data HMGitConfig = HMGitConfig {
    hmGitDir         :: P.Path P.Abs P.Dir
  , hmGitModulesFile :: Maybe (P.Path P.Abs P.File)
  , hmGitTreeLimit   :: Int
  } | HMGitConfigInit

isHMGitDir :: MonadIO m
    => P.Path P.Abs P.Dir
    -> m Bool
isHMGitDir fp = andM [
    P.doesDirExist fp
  , P.doesDirExist $ fp P.</> $(P.mkRelDir "objects")
  , P.doesDirExist $ fp P.</> $(P.mkRelDir "refs")
  ]

getHMGitPath :: (MonadThrow m, MonadIO m)
    => String
    -> m (P.Path P.Abs P.Dir)
getHMGitPath dbName = do
    currentDir <- P.getCurrentDir
    dbName' <- P.parseRelDir dbName
    ($ currentDir) . fix $ \f cwd ->
        ifM (not <$> P.doesDirExist cwd) (throw $ noSuchThing errMsg) $
            let expectedHMGitDirPath = cwd P.</> dbName' in
                ifM (isHMGitDir expectedHMGitDirPath)
                    (P.canonicalizePath expectedHMGitDirPath)
                  $ if P.parent cwd == cwd then throw $ noSuchThing errMsg else f (P.parent cwd)
    where
        errMsg = printf "not a git repository (or any of the parent directories): %s" dbName

hmGitConfig :: (MonadThrow m, MonadIO m)
    => String
    -> m HMGitConfig
hmGitConfig dbName = do
    hmGitPath <- getHMGitPath dbName
    hmGitModulesPath <- (P.parent hmGitPath P.</>) <$> P.parseRelFile (dbName <> "module")
    hmGitModulesPath' <- ifM (P.doesFileExist hmGitModulesPath)
        (pure $ Just hmGitModulesPath) $ pure Nothing
    pure $ HMGitConfig {
        hmGitDir = hmGitPath
      , hmGitModulesFile = hmGitModulesPath'
      , hmGitTreeLimit = 1000
      }

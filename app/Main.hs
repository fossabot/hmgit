module Main where

import           HMGit                              (BugException (..),
                                                     HMGitConfig (..), HMGitT,
                                                     hmGitConfig, runHMGit)
import           HMGit.Commands                     (Cmd (..))
import           HMGit.Commands.Plumbing.CatFile
import           HMGit.Commands.Plumbing.HashObject
import           HMGit.Commands.Plumbing.LsFiles
import           HMGit.Commands.Porcelain.Add
import           HMGit.Commands.Porcelain.Commit
import           HMGit.Commands.Porcelain.Diff
import           HMGit.Commands.Porcelain.Init
import           HMGit.Commands.Porcelain.Status

import           Control.Exception.Safe             (MonadCatch,
                                                     displayException, throw,
                                                     tryAny)
import           Control.Monad                      (MonadPlus, (>=>))
import           Control.Monad.IO.Class             (MonadIO)
import qualified Options.Applicative                as OA
import           Prelude                            hiding (init)
import           System.Exit                        (exitFailure)
import           System.IO                          (hPutStrLn, stderr)

data Opts m = Opts FilePath (Cmd m)

optDBName :: OA.Parser String
optDBName = OA.option OA.str $ mconcat [
    OA.long "db-name"
  , OA.value ".hmgit"
  , OA.metavar "<database name>"
  , OA.help "hmgit database name"
  ]

programOptions :: (MonadCatch m, MonadIO m, MonadPlus m) => OA.Parser (Opts m)
programOptions = Opts
    <$> optDBName
    <*> OA.hsubparser (mconcat [
        addCmd
      , catFileCmd
      , diffCmd
      , hashObjectCmd
      , initCmd
      , lsFilesCmd
      , statusCmd
      , commitCmd
      ])

optsParser :: (MonadCatch m, MonadIO m, MonadPlus m) => OA.ParserInfo (Opts m)
optsParser = OA.info (OA.helper <*> programOptions) $ mconcat [
    OA.fullDesc
  , OA.progDesc "the subset of awesome content tracker"
  ]

optsToHMGitT :: (MonadPlus m, MonadCatch m, MonadIO m) => Opts m -> m (HMGitT m (), HMGitConfig)
optsToHMGitT (Opts dbName (CmdInit runner repoName)) = pure (
    init runner dbName repoName
  , HMGitConfigInit
  )
optsToHMGitT (Opts dbName cmd) = (,)
    <$> fromCmd cmd
    <*> hmGitConfig dbName
    where
        fromCmd (CmdCatFile runner object) = pure $ catFile runner object
        fromCmd (CmdHashObject objType runner fpath) = pure $ hashObject runner objType fpath
        fromCmd (CmdLsFiles runner lsFilesCfg) = pure $ lsFiles runner lsFilesCfg
        fromCmd (CmdStatus runner statusCfg) = pure $ status runner statusCfg
        fromCmd (CmdDiff runner diffCfg) = pure $ diff runner diffCfg
        fromCmd (CmdAdd runner addCfg) = pure $ add runner addCfg
        fromCmd (CmdCommit runner commitCfg) = pure $ commit runner commitCfg
        fromCmd _ = throw $ BugException "never reach here"

main :: IO ()
main = OA.customExecParser (OA.prefs OA.showHelpOnError) optsParser
    >>= tryAny . optsToHMGitT
    >>= either
        (hPutStrLn stderr . displayException >=> const exitFailure)
        (uncurry runHMGit)


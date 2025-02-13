{-# LANGUAGE OverloadedStrings, TupleSections #-}
module HMGit.Internal.Parser.Object (
    ObjectType (..)
  , objectParser
  , treeParser
) where

import           HMGit.Internal.Parser.Core
import           HMGit.Internal.Utils       (foldChoice, hexStr, stateEmpty)

import qualified Codec.Binary.UTF8.String   as S
import           Control.Monad.Extra        (ifM)
import           Control.Monad.Loops        (unfoldrM)
import           Control.Monad.Trans        (lift)
import           Control.Monad.Trans.Maybe  (MaybeT (..), runMaybeT)
import qualified Data.ByteString.Lazy       as BL
import qualified Data.ByteString.Lazy.Char8 as BLC
import qualified Data.ByteString.Lazy.UTF8  as BLU
import           Data.List                  (isPrefixOf)
import qualified Data.List.NonEmpty         as LN
import           Data.Tuple.Extra           (secondM)
import           Numeric                    (readOct)
import qualified Path                       as P
import           System.Posix.Types         (CMode (..))
import qualified Text.Megaparsec            as M
import qualified Text.Megaparsec.Char       as MC

data ObjectType = Blob
    | Commit
    | Tree
    deriving (Eq, Enum)

instance Show ObjectType where
    show Blob   = "blob"
    show Commit = "commit"
    show Tree   = "tree"

instance Read ObjectType where
    readsPrec _ s
        | "blob" `isPrefixOf` s = [(Blob, drop 4 s)]
        | "commit" `isPrefixOf` s = [(Commit, drop 6 s)]
        | "tree" `isPrefixOf` s = [(Tree, drop 4 s)]
        | otherwise = []

pObjectTypes :: ByteStringParser ObjectType
pObjectTypes = read . BLC.unpack
    <$> foldChoice (MC.string . BLU.fromString . show) [ Blob .. Tree ]

pHeader :: Read i => ByteStringParser (ObjectType, i)
pHeader = (,)
    <$> pObjectTypes
    <*> (pSpace *> pDecimals <* pNull)

objectParser :: ByteStringParser (ObjectType, BL.ByteString)
objectParser = (pHeader >>= secondM (fmap BL.pack . flip M.count M.anySingle))
    <* M.eof

treeParser :: Int -> ByteStringParser [(CMode, P.Path P.Rel P.File, String)]
treeParser limit = runMaybeT treeParser'
    >>= maybe (M.customFailure $ TreeParser "failed to parse octet value of cmode") pure
    where
        treeParser' = flip unfoldrM 0 $ \limitCount ->
            ifM ((limitCount >= limit ||) <$> lift M.atEnd) (pure Nothing) $ do
                cmode <- stateEmpty
                    =<< LN.head
                    <$> MaybeT (LN.nonEmpty . readOct . show <$> pDecimals')
                    <* lift pSpace
                (.) Just . (.) (, succ limitCount) . (cmode,,)
                    <$> MaybeT (P.parseRelFile . S.decode <$> M.manyTill M.anySingle pNull)
                    <*> MaybeT (pure . hexStr <$> M.count 20 M.anySingle)

        pDecimals' = pDecimals :: ByteStringParser Integer

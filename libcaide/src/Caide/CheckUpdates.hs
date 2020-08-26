{-# LANGUAGE DeriveGeneric, OverloadedStrings, ScopedTypeVariables #-}
module Caide.CheckUpdates(
      parseLatestVersion
    , checkUpdates
    , logIfUpdateAvailable
) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import qualified Data.ByteString.Lazy as LBS
import Data.Maybe (listToMaybe)
import Data.Text.Encoding (encodeUtf8)
import Data.Version (Version, parseVersion)
import GHC.Generics (Generic)
import Text.ParserCombinators.ReadP (readP_to_S)

import qualified Data.Aeson as Aeson

import Paths_libcaide (version)
import Caide.GlobalState (GlobalState(latestVersion), readGlobalState, modifyGlobalState, flushGlobalState)
import Caide.Logger (logWarn)
import Caide.Types (CaideIO)
import Caide.Util (withLock)
import Network.HTTP.Util (downloadDocument)


data Release = Release
             { tag_name :: String
             , draft :: Bool
             , prerelease :: Bool
             } deriving (Generic, Show)

instance Aeson.FromJSON Release

parseLatestVersion :: LBS.ByteString -> Maybe Version
parseLatestVersion s = do
    releases :: [Release] <- Aeson.decode s
    let nonBetaReleases = [r | r <- releases, not (draft r || prerelease r)]
    latestRelease <- listToMaybe nonBetaReleases
    let tagName = tag_name latestRelease
    when (head tagName /= 'v') Nothing
    let parseResults = readP_to_S parseVersion $ tail tagName
        fullParseResults = [v | (v, "") <- parseResults]
    case fullParseResults of
        [v] -> Just v
        _   -> Nothing

checkUpdates :: CaideIO ()
checkUpdates = do
    releases <- liftIO $ downloadDocument "https://api.github.com/repos/slycelote/caide/releases"
    case releases of
        Left _ -> pure ()
        Right contents -> do
            let bsContents = LBS.fromStrict . encodeUtf8 $ contents
            case parseLatestVersion bsContents of
                Nothing  -> pure ()
                ver -> withLock $ do
                    modifyGlobalState $ \s -> s {latestVersion = ver}
                    flushGlobalState

logIfUpdateAvailable :: CaideIO ()
logIfUpdateAvailable = do
    s <- readGlobalState
    case latestVersion s of
        Just v | v > version ->
            logWarn "New version is available on GitHub: https://github.com/slycelote/caide/releases"
        _ -> pure ()


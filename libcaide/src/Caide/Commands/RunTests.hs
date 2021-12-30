{-# LANGUAGE OverloadedStrings #-}

module Caide.Commands.RunTests(
      runTests
    , evalTests
) where


import Control.Monad (forM, unless)
import Control.Monad.State (liftIO)
import Data.Either (isRight)
import Data.List (sortBy)
import Data.Maybe (isJust)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text.Read as TextRead
import qualified Data.Text as T
import qualified Data.Text.IO.Util as T

import Prelude hiding (FilePath)
import Filesystem (isFile, readTextFile, writeTextFile)
import Filesystem.Path (FilePath, (</>), basename, filename, hasExtension, replaceExtension)
import Filesystem.Util (listDir, pathToText)

import qualified Caide.Builders.None as None
import qualified Caide.Builders.Custom as Custom
import Caide.CustomBuilder (createBuilderFromDirectory)
import Caide.Configuration (getActiveProblem, readCaideConf, withDefault)
import Caide.Logger (logError)
import qualified Caide.Paths as Paths
import Caide.Problem (currentLanguage, readProblemInfo, readProblemState)
import Caide.Registry (findLanguage)
import Caide.Settings (verboseTestReport)
import Caide.Types
import Caide.TestCases.Types (ComparisonResult(..), isSuccessful,
    TestRunResult(..), makeTestRunResult,
    TestReport, humanReadableReport, humanReadableSummary, readTestReport, serializeTestReport)
import Caide.TestCases.TopcoderComparator
import Caide.Util (tshow)


createBuilderFromProblemDirectory :: ProblemID -> CaideIO (Either Text Builder)
createBuilderFromProblemDirectory probId = do
    root <- caideRoot
    createBuilderFromDirectory (Paths.problemDir root probId) []

getBuilder :: Text -> ProblemID -> CaideIO Builder
getBuilder language probId = do
    h <- readCaideConf
    let builderExists langName = withDefault False $
            (getProp h langName "build_and_run_tests" :: CaideIO Text) >> return True
        languageNames = maybe [] fst $ findLanguage language
    buildersExist <- mapM (builderExists . T.unpack) languageNames
    let existingBuilderNames = [name | (name, True) <- zip languageNames buildersExist]
    case existingBuilderNames of
        (name:_) -> return $ Custom.builder name
        [] -> do
            errOrBuilder <- createBuilderFromProblemDirectory probId
            case errOrBuilder of
                Left e -> logError e >> return None.builder
                Right b -> return b

-- TODO: pass optional problem ID
runTests :: CaideIO ()
runTests = do
    probId <- getActiveProblem
    probState <- readProblemState probId
    builder <- getBuilder (currentLanguage probState) probId
    buildResult <- builder probId
    case buildResult of
        BuildFailed -> throw "Build failed"
        TestsFailed -> throw "Tests failed"
        TestsPassed -> return ()
        NoEvalTests -> evalTests

data ComparisonOptions = ComparisonOptions
    { doublePrecision :: !Double
    , topcoderType :: !(Maybe TopcoderValue)
    }

evalTests :: CaideIO ()
evalTests = do
    probId <- getActiveProblem
    root <- caideRoot
    problem <- readProblemInfo probId
    let problemDir = Paths.problemDir root probId
        testsDir = problemDir </> Paths.testsDir
        reportFile = testsDir </> Paths.testReportFile
        cmpOptions = ComparisonOptions
            { doublePrecision = problemFloatTolerance problem
            , topcoderType = case problemType problem of
                Topcoder descr -> Just . tcMethod . tcSingleMethod $ descr
                _              -> Nothing
            }

    beVerbose <- verboseTestReport <$> caideSettings
    errorCount <- liftIO $ do
        report <- generateReport cmpOptions problemDir
        writeTextFile reportFile . serializeTestReport $ report
        T.putStrLn "Results summary\n_______________\nOutcome\tCount"
        T.putStrLn $ humanReadableSummary report
        let errors = [r | r@(_, res) <- report, isSuccessful (testRunStatus res) == Just False]
        T.putStrLn . humanReadableReport $ if beVerbose then report else errors
        return $ length errors

    unless (errorCount == 0) $
        throw $ tshow errorCount <> " tests failed!"


generateReport :: ComparisonOptions -> FilePath -> IO TestReport
generateReport cmpOptions problemDir = do
    let testDir = problemDir </> Paths.testsDir
    testList <- (map filename . filter (`hasExtension` "in") . fst) <$> listDir problemDir
    report   <- readTestReport $ testDir </> Paths.testReportFile
    let testNames = map (pathToText . basename) testList
    results <- forM testList $ \testFile -> do
        let testName = pathToText $ basename testFile
            outFile = problemDir </> Paths.testsDir </> replaceExtension testFile "out"
            etalonFile = problemDir </> replaceExtension testFile "out"
        case lookup testName report of
            Nothing -> return $ makeTestRunResult $ Error "Test was not run"
            Just res@TestRunResult{testRunStatus = Ran} -> do
                [etalonExists, outFileExists] <- mapM isFile [etalonFile, outFile]
                comparisonResult <- if not outFileExists
                   then return $ Error "Output file is missing"
                   else if etalonExists
                       then compareFiles cmpOptions <$> readTextFile etalonFile <*> readTextFile outFile
                       else return EtalonUnknown
                return $ res{testRunStatus = comparisonResult}
            Just result -> return result

    return $ sortBy (comparing fst) $ zip testNames results


compareFiles :: ComparisonOptions -> Text -> Text -> ComparisonResult
compareFiles cmpOptions etalon out = case () of
    _ | isTopcoder -> tcComparison
      | not (null errors) -> Failed $ "Line " <> tshow line <> ": " <> err
      | length actual == length expected -> Success
      | otherwise -> Failed $ "Expected " <> tshow (length expected) <> " line(s)"
  where
    Just returnValueType = topcoderType cmpOptions
    isTopcoder = isJust $ topcoderType cmpOptions
    tcComparison = maybe Success Failed $
        tcCompare returnValueType (doublePrecision cmpOptions) etalon out

    expected = T.lines . T.strip $ etalon
    actual   = T.lines . T.strip $ out
    lineComparison = zipWith (compareLines cmpOptions) expected actual
    errors = [e | e@(_, Failed _) <- zip [1::Int ..] lineComparison]
    (line, Failed err) = head errors


compareLines :: ComparisonOptions -> Text -> Text -> ComparisonResult
compareLines cmpOptions expectedLine actualLine = case () of
    _ | not (null errors) -> Failed $ T.concat ["Token ", tshow numToken, ": ", err]
      | length actual == length expected -> Success
      | otherwise   ->  Failed $ T.concat ["Expected ", tshow (length expected), " token(s)"]
  where
    expected = T.words expectedLine
    actual = T.words actualLine
    tokenComparison = zipWith (compareTokens cmpOptions) expected actual
    errors = [e | e@(_, Failed _) <- zip [1::Int ..] tokenComparison]
    (numToken, Failed err) = head errors

compareTokens :: ComparisonOptions -> Text -> Text -> ComparisonResult
compareTokens cmpOptions expected actual = case () of
    _ | expected == actual -> Success
      | areEqualDoubles (doublePrecision cmpOptions) expected actual -> Success
      | otherwise -> Failed $ T.concat ["Expected ", expected, ", found ", actual]

areEqualDoubles :: Double -> Text -> Text -> Bool
areEqualDoubles precision expected actual = isRight expectedParsed && isRight actualParsed &&
    T.null expectedRest && T.null actualRest && abs (expectedDouble - actualDouble) <= precision
  where
    expectedParsed :: Either String (Double, Text)
    expectedParsed = TextRead.double expected
    Right (expectedDouble, expectedRest) = expectedParsed
    actualParsed = TextRead.double actual
    Right (actualDouble, actualRest) = actualParsed


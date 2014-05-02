module Caide.Commands.ParseProblem(
      cmd
) where

import Control.Monad (forM_)
import Data.List (find)
import qualified Data.Text as T

import Filesystem (createDirectory, writeTextFile)
import Filesystem.Path.CurrentOS (decodeString, (</>))

import Caide.Types
import Caide.Codeforces.Parser (codeforcesParser)
import Caide.Configuration (setActiveProblem)

cmd :: CommandHandler
cmd = CommandHandler
    { command = "problem"
    , description = "Parse problem description"
    , usage = "caide problem <URL>"
    , action = parseProblem
    }

parsers :: [ProblemParser]
parsers = [codeforcesParser]

parseProblem :: CaideEnvironment -> [String] -> IO ()
parseProblem env [url] = do
    let parser = find (`matches` T.pack url) parsers
    case parser of
        Nothing -> putStrLn "This online judge is not supported"
        Just p  -> do
            parseResult <- p `parse` T.pack url
            case parseResult of
                Left err -> putStrLn $ "Encountered a problem while parsing:\n" ++ err
                Right (problem, samples) -> do
                    let problemDir = getRootDirectory env </> decodeString (problemId problem)

                    -- Prepare problem directory
                    createDirectory False problemDir

                    -- Write test cases
                    forM_ (zip samples [1::Int ..]) $ \(sample, i) -> do
                        let inFile  = problemDir </> decodeString ("case" ++ show i ++ ".in")
                            outFile = problemDir </> decodeString ("case" ++ show i ++ ".out")
                        writeTextFile inFile  $ testCaseInput sample
                        writeTextFile outFile $ testCaseOutput sample

                    -- Set active problem
                    setActiveProblem env $ problemId problem
                    putStrLn $ "Problem successfully parsed into folder " ++ problemId problem

parseProblem _ _ = putStrLn $ "Usage: " ++ usage cmd

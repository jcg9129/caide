{-# LANGUAGE OverloadedStrings #-}
module Caide.TestCases.TopcoderComparator(
      tcCompare
) where

import Data.Text (Text)

import Caide.TestCases.TopcoderDeserializer
import Caide.Types (TopcoderType(..), TopcoderValue, tcValueType, tcValueDimension)
import Caide.Util (tshow)

type Comparator a = a -> a -> Maybe Text

tokenComparator :: (Eq a, Show a) => Comparator a
tokenComparator expected actual = if expected == actual
    then Nothing
    else mkError expected actual

doubleComparator :: Double -> Comparator Double
doubleComparator precision expected actual = if abs (expected - actual) <= precision
    then Nothing
    else mkError expected actual

listComparator :: Comparator a -> Comparator [a]
listComparator elemComparator expected actual = if length expected /= length actual
    then Just $
        "Different list lengths: expected " <> tshow (length expected) <> " got " <> tshow (length actual)
    else case failedComparisons of
        []            -> Nothing
        ((i, err):_)  -> Just $ "Elements " <> tshow i <> " differ: " <> err
  where
   comparisonResults = zip [1::Int ..] $ zipWith elemComparator expected actual
   failedComparisons = [(i, err) | (i, Just err) <- comparisonResults]

mkError :: (Show a) => a -> a -> Maybe Text
mkError expected actual = Just $ "Expected " <> tshow expected <> ", got " <> tshow actual


tcCompare :: TopcoderValue -> Double -> Text -> Text -> Maybe Text
tcCompare topcoderValue doublePrecision expectedText actualText = case tcValueDimension topcoderValue of
    0 -> case baseType of
        TCDouble -> eval d
        TCString -> eval s
        _        -> eval t

    1 -> case baseType of
        TCDouble -> eval $ v d
        TCString -> eval $ v s
        _        -> eval $ v t

    2 -> case baseType of
        TCDouble -> eval $ v $ v d
        TCString -> eval $ v $ v s
        _        -> eval $ v $ v t

    3 -> case baseType of
        TCDouble -> eval $ v $ v $ v d
        TCString -> eval $ v $ v $ v s
        _        -> eval $ v $ v $ v t

    _ -> Just "Dimension of return value is too high"
  where
    baseType = tcValueType topcoderValue
    s = (readQuotedString, tokenComparator)
    d = (readDouble, doubleComparator doublePrecision)
    t = (readToken, tokenComparator)

    v :: (Parser a, Comparator a) -> (Parser [a], Comparator [a])
    v (parser, comparator) = (readMany parser, listComparator comparator)

    eval :: (Parser a, Comparator a) -> Maybe Text
    eval (parser, comparator) = case (runParser parser expectedText, runParser parser actualText) of
        (Left err, _) -> Just $ "Couldn't parse expected value: " <> err
        (_, Left err) -> Just $ "Couldn't parse returned value: " <> err
        (Right expected, Right actual) -> comparator expected actual

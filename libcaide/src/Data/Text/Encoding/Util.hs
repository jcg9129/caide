{-# LANGUAGE OverloadedStrings #-}
module Data.Text.Encoding.Util(
      describeUnicodeException
    , tryDecodeUtf8
    , safeDecodeUtf8
    , universalNewlineConversionOnInput
    , universalNewlineConversionOnOutput
) where

import Data.ByteString (ByteString)
import Data.Text.Encoding (decodeUtf8', decodeUtf8With)
import Data.Text.Encoding.Error (UnicodeException, lenientDecode)
import qualified Data.Text as T

import System.IO (nativeNewline, Newline(CRLF))

describeUnicodeException :: UnicodeException -> T.Text
describeUnicodeException = T.pack . show

tryDecodeUtf8 :: ByteString -> Either T.Text T.Text
tryDecodeUtf8 = either (Left . describeUnicodeException) Right . decodeUtf8'

-- | Replaces invalid input bytes with the Unicode replacement character U+FFFD (question mark in a rhombus)
safeDecodeUtf8 :: ByteString -> T.Text
safeDecodeUtf8 = decodeUtf8With lenientDecode


nativeCallsForConversion :: Bool
nativeCallsForConversion = nativeNewline == CRLF

strLF :: T.Text
strLF = "\n"

strCRLF :: T.Text
strCRLF = "\r\n"

universalNewlineConversionOnInput :: T.Text -> T.Text
universalNewlineConversionOnInput =
  if nativeCallsForConversion
  then T.replace strCRLF strLF
  else id

universalNewlineConversionOnOutput :: T.Text -> T.Text
universalNewlineConversionOnOutput =
  if nativeCallsForConversion
  then T.replace strLF strCRLF
  else id


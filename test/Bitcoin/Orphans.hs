{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}

module Bitcoin.Orphans where

import Bitcoin
import Control.Monad
import Data.Aeson
import Data.Aeson.Encoding
import Data.ByteString.Builder (char7)
import qualified Data.ByteString.Lazy as BL
import Data.Bytes.Get
import Data.Bytes.Put
import Data.Bytes.Serial
import Data.Maybe
import Data.Scientific
import Data.String.Conversions


instance FromJSON BlockHash where
    parseJSON =
        withText "BlockHash" $
            maybe mzero return . hexToBlockHash


instance ToJSON BlockHash where
    toJSON = String . blockHashToHex
    toEncoding h =
        unsafeToEncoding $
            char7 '"'
                <> hexBuilder (BL.reverse (runPutL (serialize h)))
                <> char7 '"'


instance ToJSON BlockHeader where
    toJSON (BlockHeader v p m t b n) =
        object
            [ "version" .= v
            , "prevblock" .= p
            , "merkleroot" .= encodeHex (runPutS (serialize m))
            , "timestamp" .= t
            , "bits" .= b
            , "nonce" .= n
            ]
    toEncoding (BlockHeader v p m t b n) =
        pairs
            ( "version"
                .= v
                <> "prevblock"
                .= p
                <> "merkleroot"
                .= encodeHex (runPutS (serialize m))
                <> "timestamp"
                .= t
                <> "bits"
                .= b
                <> "nonce"
                .= n
            )


instance FromJSON BlockHeader where
    parseJSON =
        withObject "BlockHeader" $ \o ->
            BlockHeader
                <$> o
                    .: "version"
                <*> o
                    .: "prevblock"
                <*> (f =<< o .: "merkleroot")
                <*> o
                    .: "timestamp"
                <*> o
                    .: "bits"
                <*> o
                    .: "nonce"
      where
        f = maybe mzero return . (eitherToMaybe . runGetS deserialize <=< decodeHex)


instance FromJSON TxHash where
    parseJSON =
        withText "txid" $
            maybe mzero return . hexToTxHash


instance ToJSON TxHash where
    toJSON = String . txHashToHex
    toEncoding h =
        unsafeToEncoding $
            char7 '"'
                <> hexBuilder (BL.reverse (runPutL (serialize h)))
                <> char7 '"'


instance FromJSON OutPoint where
    parseJSON =
        withObject "OutPoint" $ \o ->
            OutPoint <$> o .: "txid" <*> o .: "index"


instance ToJSON OutPoint where
    toJSON (OutPoint h i) = object ["txid" .= h, "index" .= i]
    toEncoding (OutPoint h i) = pairs ("txid" .= h <> "index" .= i)


instance FromJSON TxIn where
    parseJSON =
        withObject "TxIn" $ \o ->
            TxIn
                <$> o
                    .: "prevoutput"
                <*> (maybe mzero return . decodeHex =<< o .: "inputscript")
                <*> o
                    .: "sequence"


instance ToJSON TxIn where
    toJSON (TxIn o s q) =
        object
            [ "prevoutput" .= o
            , "inputscript" .= encodeHex s
            , "sequence" .= q
            ]
    toEncoding (TxIn o s q) =
        pairs
            ( "prevoutput"
                .= o
                <> "inputscript"
                .= encodeHex s
                <> "sequence"
                .= q
            )


instance FromJSON TxOut where
    parseJSON =
        withObject "TxOut" $ \o ->
            TxOut
                <$> o
                    .: "value"
                <*> (maybe mzero return . decodeHex =<< o .: "outputscript")


instance ToJSON TxOut where
    toJSON (TxOut o s) =
        object ["value" .= o, "outputscript" .= encodeHex s]
    toEncoding (TxOut o s) =
        pairs ("value" .= o <> "outputscript" .= encodeHex s)


instance FromJSON Tx where
    parseJSON = withObject "Tx" $ \o ->
        Tx
            <$> o
                .: "version"
            <*> o
                .: "inputs"
            <*> o
                .: "outputs"
            <*> (mapM (mapM f) =<< o .: "witnessdata")
            <*> o
                .: "locktime"
      where
        f = maybe mzero return . decodeHex


instance ToJSON Tx where
    toJSON (Tx v i o w l) =
        object
            [ "version" .= v
            , "inputs" .= i
            , "outputs" .= o
            , "witnessdata" .= fmap (fmap encodeHex) w
            , "locktime" .= l
            ]
    toEncoding (Tx v i o w l) =
        pairs
            ( "version"
                .= v
                <> "inputs"
                .= i
                <> "outputs"
                .= o
                <> "witnessdata"
                .= fmap (fmap encodeHex) w
                <> "locktime"
                .= l
            )


instance ToJSON Block where
    toJSON (Block h t) = object ["header" .= h, "transactions" .= t]
    toEncoding (Block h t) = pairs $ "header" .= h <> "transactions" .= t


instance FromJSON Block where
    parseJSON =
        withObject "Block" $ \o ->
            Block <$> o .: "header" <*> o .: "transactions"


instance ToJSON (DerivPathI t) where
    toJSON = String . cs . pathToStr
    toEncoding = text . cs . pathToStr


instance FromJSON DerivPath where
    parseJSON = withText "DerivPath" $ \str -> case parsePath $ cs str of
        Just p -> return $ getParsedPath p
        _ -> mzero


instance ToJSON ParsedPath where
    toJSON (ParsedPrv p) = String . cs . ("m" ++) . pathToStr $ p
    toJSON (ParsedPub p) = String . cs . ("M" ++) . pathToStr $ p
    toJSON (ParsedEmpty p) = String . cs . ("" ++) . pathToStr $ p
    toEncoding (ParsedPrv p) = text . cs . ("m" ++) . pathToStr $ p
    toEncoding (ParsedPub p) = text . cs . ("M" ++) . pathToStr $ p
    toEncoding (ParsedEmpty p) = text . cs . ("" ++) . pathToStr $ p


instance FromJSON ParsedPath where
    parseJSON = withText "ParsedPath" $ \str -> case parsePath $ cs str of
        Just p -> return p
        _ -> mzero


instance FromJSON HardPath where
    parseJSON = withText "HardPath" $ \str -> case parseHard $ cs str of
        Just p -> return p
        _ -> mzero


instance FromJSON SoftPath where
    parseJSON = withText "SoftPath" $ \str -> case parseSoft $ cs str of
        Just p -> return p
        _ -> mzero


instance ToJSON PubKeyI where
    toJSON = String . encodeHex . runPutS . serialize
    toEncoding s =
        unsafeToEncoding $
            char7 '"'
                <> hexBuilder (runPutL (serialize s))
                <> char7 '"'


instance FromJSON PubKeyI where
    parseJSON =
        withText "PubKeyI" $
            maybe mzero return . ((eitherToMaybe . runGetS deserialize) <=< decodeHex)


instance FromJSON SigHash where
    parseJSON =
        withScientific "sighash" $
            maybe mzero (return . SigHash) . toBoundedInteger


instance ToJSON SigHash where
    toJSON = Number . fromIntegral
    toEncoding (SigHash n) = toEncoding n


instance FromJSON ScriptOutput where
    parseJSON =
        withText "scriptoutput" $ \t ->
            either fail return $
                maybeToEither "scriptoutput not hex" (decodeHex t)
                    >>= decodeOutputBS


instance ToJSON ScriptOutput where
    toJSON = String . encodeHex . encodeOutputBS
    toEncoding = text . encodeHex . encodeOutputBS


instance ToJSON SigInput where
    toJSON (SigInput so val op sh rdm) =
        object $
            [ "pkscript" .= so
            , "value" .= val
            , "outpoint" .= op
            , "sighash" .= sh
            ]
                ++ ["redeem" .= r | r <- maybeToList rdm]
    toEncoding (SigInput so val op sh rdm) =
        pairs $
            "pkscript"
                .= so
                <> "value"
                .= val
                <> "outpoint"
                .= op
                <> "sighash"
                .= sh
                <> maybe mempty ("redeem" .=) rdm


instance FromJSON SigInput where
    parseJSON =
        withObject "SigInput" $ \o ->
            SigInput
                <$> o
                    .: "pkscript"
                <*> o
                    .: "value"
                <*> o
                    .: "outpoint"
                <*> o
                    .: "sighash"
                <*> o
                    .:? "redeem"


-- | Hex encoding
instance FromJSON XOnlyPubKey where
    parseJSON =
        withText "XOnlyPubKey" $
            either fail pure
                . (runGetS deserialize <=< maybe (Left "Unable to decode hex") Right . decodeHex)

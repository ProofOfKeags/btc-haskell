{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}

-- |
-- Stability   : experimental
-- Portability : POSIX
--
-- Transaction signatures and related functions.
module Bitcoin.Script.SigHash (
    -- * Script Signatures
    SigHash (..),
    SigHashFlag (..),
    sigHashAll,
    sigHashNone,
    sigHashSingle,
    hasAnyoneCanPayFlag,
    setAnyoneCanPayFlag,
    isSigHashAll,
    isSigHashNone,
    isSigHashSingle,
    isSigHashUnknown,
    txSigHash,
    txSigHashSegwitV0,
    TxSignature (..),
    encodeTxSig,
    decodeTxSig,
) where

import Bitcoin.Crypto (
    Hash256,
    Signature,
    decodeStrictSig,
    putSig,
 )
import Bitcoin.Crypto.Hash (doubleSHA256L)
import Bitcoin.Data (Network)
import Bitcoin.Network.Common (putVarInt)
import Bitcoin.Script.Common (
    Script (..),
    ScriptOp (OP_CODESEPARATOR),
 )
import Bitcoin.Transaction.Common (Tx (..), TxIn (..), TxOut (TxOut))
import Bitcoin.Util (updateIndex)
import qualified Bitcoin.Util as U
import Control.DeepSeq (NFData)
import Control.Monad (when)
import Data.Binary (put)
import qualified Data.Binary as Bin
import Data.Binary.Put (
    putLazyByteString,
    putWord32le,
    putWord64le,
    putWord8,
    runPut,
 )
import Data.Bits (Bits ((.&.), (.|.)))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import Data.Hashable (Hashable)
import Data.Maybe (fromMaybe)
import Data.Word (Word32, Word64)
import GHC.Generics (Generic)


-- | Constant representing a SIGHASH flag that controls what is being signed.
data SigHashFlag
    = -- | sign all outputs
      SIGHASH_ALL
    | -- | sign no outputs
      SIGHASH_NONE
    | -- | sign the output index corresponding to the input
      SIGHASH_SINGLE
    | -- | new inputs can be added
      SIGHASH_ANYONECANPAY
    deriving (Eq, Ord, Show, Read, Generic)


instance NFData SigHashFlag


instance Hashable SigHashFlag


instance Enum SigHashFlag where
    fromEnum SIGHASH_ALL = 0x01
    fromEnum SIGHASH_NONE = 0x02
    fromEnum SIGHASH_SINGLE = 0x03
    fromEnum SIGHASH_ANYONECANPAY = 0x80
    toEnum 0x01 = SIGHASH_ALL
    toEnum 0x02 = SIGHASH_NONE
    toEnum 0x03 = SIGHASH_SINGLE
    toEnum 0x80 = SIGHASH_ANYONECANPAY
    toEnum _ = error "Not a valid sighash flag"


-- | Data type representing the different ways a transaction can be signed.
-- When producing a signature, a hash of the transaction is used as the message
-- to be signed. The 'SigHash' parameter controls which parts of the
-- transaction are used or ignored to produce the transaction hash. The idea is
-- that if some part of a transaction is not used to produce the transaction
-- hash, then you can change that part of the transaction after producing a
-- signature without invalidating that signature.
--
-- If the 'SIGHASH_ANYONECANPAY' flag is set (true), then only the current input
-- is signed. Otherwise, all of the inputs of a transaction are signed. The
-- default value for 'SIGHASH_ANYONECANPAY' is unset (false).
newtype SigHash
    = SigHash Word32
    deriving
        ( Eq
        , Ord
        , Bits
        , Enum
        , Integral
        , Num
        , Real
        , Show
        , Read
        , Generic
        , Hashable
        , NFData
        )


-- | SIGHASH_NONE as a byte.
sigHashNone :: SigHash
sigHashNone = fromIntegral $ fromEnum SIGHASH_NONE


-- | SIGHASH_ALL as a byte.
sigHashAll :: SigHash
sigHashAll = fromIntegral $ fromEnum SIGHASH_ALL


-- | SIGHASH_SINGLE as a byte.
sigHashSingle :: SigHash
sigHashSingle = fromIntegral $ fromEnum SIGHASH_SINGLE


-- | SIGHASH_ANYONECANPAY as a byte.
sigHashAnyoneCanPay :: SigHash
sigHashAnyoneCanPay = fromIntegral $ fromEnum SIGHASH_ANYONECANPAY


-- | Set SIGHASH_ANYONECANPAY flag.
setAnyoneCanPayFlag :: SigHash -> SigHash
setAnyoneCanPayFlag = (.|. sigHashAnyoneCanPay)


-- | Is the SIGHASH_ANYONECANPAY flag set?
hasAnyoneCanPayFlag :: SigHash -> Bool
hasAnyoneCanPayFlag = (/= 0) . (.&. sigHashAnyoneCanPay)


-- | Returns 'True' if the 'SigHash' has the value 'SIGHASH_ALL'.
isSigHashAll :: SigHash -> Bool
isSigHashAll = (== sigHashAll) . (.&. 0x1f)


-- | Returns 'True' if the 'SigHash' has the value 'SIGHASH_NONE'.
isSigHashNone :: SigHash -> Bool
isSigHashNone = (== sigHashNone) . (.&. 0x1f)


-- | Returns 'True' if the 'SigHash' has the value 'SIGHASH_SINGLE'.
isSigHashSingle :: SigHash -> Bool
isSigHashSingle = (== sigHashSingle) . (.&. 0x1f)


-- | Returns 'True' if the 'SigHash' has the value 'SIGHASH_UNKNOWN'.
isSigHashUnknown :: SigHash -> Bool
isSigHashUnknown =
    (`notElem` [sigHashAll, sigHashNone, sigHashSingle]) . (.&. 0x1f)


-- | Computes the hash that will be used for signing a transaction.
txSigHash ::
    Network ->
    -- | transaction to sign
    Tx ->
    -- | script from output being spent
    Script ->
    -- | value of output being spent
    Word64 ->
    -- | index of input being signed
    Int ->
    -- | what to sign
    SigHash ->
    -- | hash to be signed
    Hash256
txSigHash _net tx out _v i sh = do
    let newIn = buildInputs (txIn tx) fout i sh
    -- When SigSingle and input index > outputs, then sign integer 1
    fromMaybe one $ do
        newOut <- buildOutputs (txOut tx) i sh
        let newTx = Tx (txVersion tx) newIn newOut [] (txLockTime tx)
        return
            . doubleSHA256L
            . runPut
            $ do
                put newTx
                putWord32le $ fromIntegral sh
  where
    fout = Script $ filter (/= OP_CODESEPARATOR) $ scriptOps out
    one = "0100000000000000000000000000000000000000000000000000000000000000"


-- | Build transaction inputs for computing sighashes.
buildInputs :: [TxIn] -> Script -> Int -> SigHash -> [TxIn]
buildInputs txins out i sh
    | hasAnyoneCanPayFlag sh =
        [(txins !! i){scriptInput}]
    | isSigHashAll sh || isSigHashUnknown sh = single
    | otherwise = zipWith noSeq single [0 ..]
  where
    emptyIn = map (\ti -> ti{scriptInput = BS.empty}) txins
    single = updateIndex i emptyIn $ \ti -> ti{scriptInput}
    scriptInput = U.encodeS out
    noSeq ti j =
        if i == j
            then ti
            else ti{txInSequence = 0}


-- | Build transaction outputs for computing sighashes.
buildOutputs :: [TxOut] -> Int -> SigHash -> Maybe [TxOut]
buildOutputs txos i sh
    | isSigHashAll sh || isSigHashUnknown sh = return txos
    | isSigHashNone sh = return []
    | i >= length txos = Nothing
    | otherwise = return $ buffer ++ [txos !! i]
  where
    buffer = replicate i $ TxOut maxBound BS.empty


-- | Compute the hash that will be used for signing a transaction. This
-- function is used when the 'SIGHASH_FORKID' flag is set.
txSigHashSegwitV0 ::
    Network ->
    -- | transaction to sign
    Tx ->
    -- | script from output being spent
    Script ->
    -- | value of output being spent
    Word64 ->
    -- | index of input being signed
    Int ->
    -- | what to sign
    SigHash ->
    -- | hash to be signed
    Hash256
txSigHashSegwitV0 _ tx out v i sh =
    doubleSHA256L . runPut $ do
        putWord32le $ txVersion tx
        put hashPrevouts
        put hashSequence
        put $ prevOutput $ txIn tx !! i
        putScript out
        putWord64le v
        putWord32le $ txInSequence $ txIn tx !! i
        put hashOutputs
        putWord32le $ txLockTime tx
        putWord32le $ fromIntegral sh
  where
    hashPrevouts
        | not $ hasAnyoneCanPayFlag sh =
            doubleSHA256L . runPut . mapM_ (put . prevOutput) $ txIn tx
        | otherwise = zeros
    hashSequence
        | not (hasAnyoneCanPayFlag sh)
            && not (isSigHashSingle sh)
            && not (isSigHashNone sh) =
            doubleSHA256L . runPut . mapM_ (putWord32le . txInSequence) $ txIn tx
        | otherwise = zeros
    hashOutputs
        | not (isSigHashSingle sh) && not (isSigHashNone sh) =
            doubleSHA256L . runPut . mapM_ put $ txOut tx
        | isSigHashSingle sh && i < length (txOut tx) =
            doubleSHA256L . Bin.encode $ txOut tx !! i
        | otherwise = zeros
    putScript s = do
        let encodedScript = Bin.encode s
        putVarInt $ BSL.length encodedScript
        putLazyByteString encodedScript
    zeros :: Hash256
    zeros = "0000000000000000000000000000000000000000000000000000000000000000"


-- | Data type representing a signature together with a 'SigHash'. The 'SigHash'
-- is serialized as one byte at the end of an ECDSA 'Sig'. All signatures in
-- transaction inputs are of type 'TxSignature'.
data TxSignature
    = TxSignature
        { txSignature :: !Signature
        , txSignatureSigHash :: !SigHash
        }
    | TxSignatureEmpty
    deriving (Eq, Show, Generic)


instance NFData TxSignature


-- | Serialize a 'TxSignature'.
encodeTxSig :: TxSignature -> BS.ByteString
encodeTxSig TxSignatureEmpty = error "Can not encode an empty signature"
encodeTxSig (TxSignature sig (SigHash n)) =
    BSL.toStrict . runPut $ putSig sig >> putWord8 (fromIntegral n)


-- | Deserialize a 'TxSignature'.
decodeTxSig :: Network -> BS.ByteString -> Either String TxSignature
-- TODO remove unused parameter
decodeTxSig _ bs | BS.null bs = Left "Empty signature candidate"
decodeTxSig _net bs =
    case decodeStrictSig $ BS.init bs of
        Just sig -> do
            let sh = fromIntegral $ BS.last bs
            when (isSigHashUnknown sh) $
                Left "Non-canonical signature: unknown hashtype byte"
            return $ TxSignature sig sh
        Nothing -> Left "Non-canonical signature: could not parse signature"

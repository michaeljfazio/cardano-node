{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}


-- | Transaction bodies
--
module Cardano.Api.TxBody (

    -- * Transaction bodies
    TxBody(..),
    makeTransactionBody,
    TxBodyContent(..),
    TxBodyError(..),

    -- ** Transitional utils
    makeByronTransaction,
    makeShelleyTransaction,

    -- * Transaction Ids
    TxId(..),
    getTxId,

    -- * Transaction inputs
    TxIn(..),
    TxIx(..),
    TxInTypeInEra(..),
    genesisUTxOPseudoTxIn,
    plutusScriptsSupportedInEra,

    -- * Transaction outputs
    TxOut(..),
    TxOutValue(..),
    DataHash(..),

    -- * Tx witnesses
    WitnessKind(..),

    -- ** Plutus script
    RedeemerPointer(..),


    -- * Other transaction body types
    TxFee(..),
    TxValidityLowerBound(..),
    TxValidityUpperBound(..),
    TxMetadataInEra(..),
    TxAuxScripts(..),
    TxWithdrawals(..),
    TxCertificates(..),
    TxUpdateProposal(..),
    TxMintValue(..),

    -- * Era-dependent transaction body features
    MultiAssetSupportedInEra(..),
    OnlyAdaSupportedInEra(..),
    TxFeesExplicitInEra(..),
    TxFeesImplicitInEra(..),
    ValidityUpperBoundSupportedInEra(..),
    ValidityNoUpperBoundSupportedInEra(..),
    ValidityLowerBoundSupportedInEra(..),
    TxMetadataSupportedInEra(..),
    AuxScriptsSupportedInEra(..),
    WithdrawalsSupportedInEra(..),
    CertificatesSupportedInEra(..),
    UpdateProposalSupportedInEra(..),
    TxExecutionUnits(..),
    TxWitnessPPData(..),
    WitnessPPDataSupportedInEra(..),
    PlutusScriptsSupportedInEra(..),
    CertificateTypeInEra(..),
    WithdrawalsTypeInEra(..),
    TxInUsedForFees(..),

    -- ** Feature availability functions
    multiAssetSupportedInEra,
    txFeesExplicitInEra,
    validityUpperBoundSupportedInEra,
    validityNoUpperBoundSupportedInEra,
    validityLowerBoundSupportedInEra,
    txMetadataSupportedInEra,
    auxScriptsSupportedInEra,
    withdrawalsSupportedInEra,
    certificatesSupportedInEra,
    updateProposalSupportedInEra,
    executionUnitsSupportedInEra,
    witnessPPDataSupportedInEra,

    -- * Internal conversion functions & types
    toShelleyTxId,
    toShelleyTxIn,
    toShelleyTxOut,
    fromShelleyTxId,
    fromShelleyTxIn,
    fromShelleyTxOut,
    fromTxOut,

    -- * Data family instances
    AsType(AsTxId, AsTxBody, AsByronTxBody, AsShelleyTxBody),

    -- * Conversion functions
    fromByronTxIn,
  ) where

import           Prelude

import           Data.Aeson (ToJSON (..), object, (.=))
import qualified Data.Aeson as Aeson
import           Data.Aeson.Types (ToJSONKey (..), toJSONKeyText)
import           Data.Bifunctor (first)
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import           Data.List (intercalate)
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import           Data.Maybe (fromMaybe, mapMaybe)
import qualified Data.Sequence.Strict as Seq
import qualified Data.Set as Set
import           Data.String (IsString)
import           Data.Text (Text)
import qualified Data.Text as Text
import           Data.Word (Word64)
import           GHC.Generics

import           Control.Monad (guard)

import           Cardano.Binary (Annotated (..), reAnnotate, recoverBytes)
import qualified Cardano.Binary as CBOR
import qualified Shelley.Spec.Ledger.Serialization as CBOR (decodeNullMaybe, encodeNullMaybe)

import qualified Cardano.Crypto.Hash.Class as Crypto
import           Cardano.Slotting.Slot (SlotNo (..))

import qualified Cardano.Chain.Common as Byron
import qualified Cardano.Chain.UTxO as Byron
import qualified Cardano.Crypto.Hashing as Byron

import qualified Cardano.Ledger.Alonzo as Alonzo
import qualified Cardano.Ledger.Alonzo.Tx as Alonzo
import qualified Cardano.Ledger.Alonzo.TxBody as Alonzo
import qualified Cardano.Ledger.AuxiliaryData as Ledger (hashAuxiliaryData)
import qualified Cardano.Ledger.Core as Core
import qualified Cardano.Ledger.Core as Ledger
import qualified Cardano.Ledger.Era as Ledger
import qualified Cardano.Ledger.SafeHash as SafeHash
import qualified Cardano.Ledger.Shelley.Constraints as Ledger
import qualified Cardano.Ledger.ShelleyMA.AuxiliaryData as Allegra
import qualified Cardano.Ledger.ShelleyMA.TxBody as Allegra
import           Ouroboros.Consensus.Shelley.Eras (StandardAllegra, StandardMary, StandardShelley)
import           Ouroboros.Consensus.Shelley.Protocol.Crypto (StandardCrypto)

import qualified Shelley.Spec.Ledger.Address as Shelley
import           Shelley.Spec.Ledger.BaseTypes (StrictMaybe (..), maybeToStrictMaybe)
import qualified Shelley.Spec.Ledger.Credential as Shelley
import qualified Shelley.Spec.Ledger.Genesis as Shelley
import qualified Shelley.Spec.Ledger.Keys as Shelley
import qualified Shelley.Spec.Ledger.Metadata as Shelley
import qualified Shelley.Spec.Ledger.Tx as Shelley
import qualified Shelley.Spec.Ledger.TxBody as Shelley
import qualified Shelley.Spec.Ledger.UTxO as Shelley

--import qualified Cardano.Ledger.Alonzo.TxBody as Alonzo
import qualified Cardano.Ledger.Alonzo.Data as Alonzo

import           Cardano.Api.Address
import           Cardano.Api.Certificate
import           Cardano.Api.Eras
import           Cardano.Api.Error
import           Cardano.Api.HasTypeProxy
import           Cardano.Api.Hash
import           Cardano.Api.KeysByron
import           Cardano.Api.KeysShelley
import           Cardano.Api.NetworkId
import           Cardano.Api.ProtocolParameters
import           Cardano.Api.Script
import           Cardano.Api.SerialiseCBOR
import           Cardano.Api.SerialiseRaw
import           Cardano.Api.SerialiseTextEnvelope
import           Cardano.Api.TxMetadata
import           Cardano.Api.Utils
import           Cardano.Api.Value


-- ----------------------------------------------------------------------------
-- Transaction Ids
--

newtype TxId = TxId (Shelley.Hash StandardCrypto Shelley.EraIndependentTxBody)
  deriving stock (Eq, Ord, Show)
  deriving newtype (IsString)
               -- We use the Shelley representation and convert the Byron one

instance ToJSON TxId where
  toJSON = Aeson.String . serialiseToRawBytesHexText

instance HasTypeProxy TxId where
    data AsType TxId = AsTxId
    proxyToAsType _ = AsTxId

instance SerialiseAsRawBytes TxId where
    serialiseToRawBytes (TxId h) = Crypto.hashToBytes h
    deserialiseFromRawBytes AsTxId bs = TxId <$> Crypto.hashFromBytes bs

toByronTxId :: TxId -> Byron.TxId
toByronTxId (TxId h) =
    Byron.unsafeHashFromBytes (Crypto.hashToBytes h)

toShelleyTxId :: TxId -> Shelley.TxId StandardCrypto
toShelleyTxId (TxId h) =
    Shelley.TxId (SafeHash.unsafeMakeSafeHash (Crypto.castHash h))

fromShelleyTxId :: Shelley.TxId StandardCrypto -> TxId
fromShelleyTxId (Shelley.TxId h) =
    TxId (Crypto.castHash (SafeHash.extractHash h))

-- | Calculate the transaction identifier for a 'TxBody'.
--
getTxId :: forall era. TxBody era -> TxId
getTxId (ByronTxBody tx) =
    TxId
  . fromMaybe impossible
  . Crypto.hashFromBytesShort
  . Byron.abstractHashToShort
  . Byron.hashDecoded
  $ tx
  where
    impossible =
      error "getTxId: byron and shelley hash sizes do not match"

getTxId (ShelleyTxBody era tx _ _) =
    case era of
      ShelleyBasedEraShelley -> getTxIdShelley tx
      ShelleyBasedEraAllegra -> getTxIdShelley tx
      ShelleyBasedEraMary    -> getTxIdShelley tx
      ShelleyBasedEraAlonzo  -> getTxIdShelley tx
  where
    getTxIdShelley :: Ledger.Crypto (ShelleyLedgerEra era) ~ StandardCrypto
                   => Ledger.UsesTxBody (ShelleyLedgerEra era)
                   => Ledger.TxBody (ShelleyLedgerEra era) -> TxId
    getTxIdShelley =
        TxId
      . Crypto.castHash
      . (\(Shelley.TxId txhash) -> SafeHash.extractHash txhash)
      . (Shelley.txid @(ShelleyLedgerEra era))


-- ----------------------------------------------------------------------------
-- Transaction inputs
--

data TxIn where
  TxIn :: TxId -> TxIx -> TxIn

deriving instance Eq   TxIn
deriving instance Ord  TxIn
deriving instance Show TxIn

-- | Specify if a transaction input will be used as a Plutus fee.
data TxInUsedForFees era where
  TxInNotInUseForFees :: TxInUsedForFees era
  TxInUsedForFees :: PlutusScriptsSupportedInEra era -> TxInUsedForFees era

data PlutusScriptsSupportedInEra era where

     PlutusScriptsInAlonzoEra :: PlutusScriptsSupportedInEra AlonzoEra

deriving instance Eq   (PlutusScriptsSupportedInEra era)
deriving instance Ord  (PlutusScriptsSupportedInEra era)
deriving instance Show (PlutusScriptsSupportedInEra era)

plutusScriptsSupportedInEra :: CardanoEra era
                            -> Maybe (PlutusScriptsSupportedInEra era)
plutusScriptsSupportedInEra ByronEra   = Nothing
plutusScriptsSupportedInEra ShelleyEra = Nothing
plutusScriptsSupportedInEra AllegraEra = Nothing
plutusScriptsSupportedInEra MaryEra    = Nothing
plutusScriptsSupportedInEra AlonzoEra  = Just PlutusScriptsInAlonzoEra

-- | This labels a TxIn that will be used
--for spending a UTxO locked by a non-native script (e.g Plutus Core).
--I.E the 'TxIn' is being used to execute a non-native
--script (e.g Plutus Core) and the 'TxIn' is /NOT/ locked by a non-native script.
data TxInTypeInEra era where
  PlutusFee           :: PlutusScriptsSupportedInEra era -> TxInTypeInEra era
  PlutusSpendingInput :: PlutusScriptsSupportedInEra era
                      -> Maybe ScriptDatum -> TxInTypeInEra era
  NotPlutusInput      :: TxInTypeInEra era

deriving instance Eq   (TxInTypeInEra era)
deriving instance Ord  (TxInTypeInEra era)
deriving instance Show (TxInTypeInEra era)

-- ----------------------------------------------------------------------------
-- The kind of witness to use, key (signature) or script
--

data WitnessKind witctx era where
   WitnessByKey :: WitnessKind witctx era
   WitnessByScript :: ScriptWitness witctx era -> WitnessKind witctx era

-- | The 'RedeemerPointer' gives us the index
-- at which the redeemer exists within a transaction body.

data RedeemerPointer =
    CertificateRedeemer Word64
    -- ^ Gives us the index of a certificate.
  | MintingRedeemer Word64
    -- ^ Gives us the index of a multi-asset.
  | SpendingRedeemer Word64
    -- ^ Gives us the index of a transaction input.
  | RewardingRedeemer Word64
    -- ^ Gives us the index of the withdrawal certificate.

makeTxWitnessPPDataHash
  :: ScriptLanguageInEra lang era
  -> TxWitnessPPData era -- Strictly plutus tagged things
  -- All txins, certs, outs and withdrawls. Need these to determine the index
  -> [TxIn]
  -> TxCertificates era
  -> [TxOut era]
  -> TxWithdrawals era
  -> Maybe Text -- Placeholder. Should be: Maybe (WitnessPPDataHash (Crypto era)
makeTxWitnessPPDataHash _ TxWitnessPPDataNone _ _ _ _ = Nothing
makeTxWitnessPPDataHash _sLangInEra (TxWitnessPPData _pparams _txins')
                        _txins _txcerts _txouts _txWithdrawals =
-- Create redeemer map her
   Nothing


instance ToJSON TxIn  where
  toJSON txIn = Aeson.String $ renderTxIn txIn

instance ToJSONKey TxIn where
  toJSONKey = toJSONKeyText renderTxIn

renderTxIn :: TxIn -> Text
renderTxIn (TxIn txId (TxIx ix)) =
  serialiseToRawBytesHexText txId <> "#" <> Text.pack (show ix)


newtype TxIx = TxIx Word
  deriving stock (Eq, Ord, Show)
  deriving newtype (Enum)
  deriving newtype ToJSON

fromByronTxIn :: Byron.TxIn -> TxIn
fromByronTxIn (Byron.TxInUtxo txId index) =
  let shortBs = Byron.abstractHashToShort txId
      mApiHash = Crypto.hashFromBytesShort shortBs
  in case mApiHash of
       Just apiHash -> TxIn (TxId apiHash) (TxIx . fromIntegral $ toInteger index)
       Nothing -> error $ "Error converting Byron era TxId: " <> show txId

toByronTxIn :: TxIn -> Byron.TxIn
toByronTxIn (TxIn txid (TxIx txix)) =
    Byron.TxInUtxo (toByronTxId txid) (fromIntegral txix)

toShelleyTxIn :: TxIn -> Shelley.TxIn StandardCrypto
toShelleyTxIn (TxIn txid (TxIx txix)) =
    Shelley.TxIn (toShelleyTxId txid) (fromIntegral txix)


fromShelleyTxIn :: Shelley.TxIn StandardCrypto -> TxIn
fromShelleyTxIn (Shelley.TxIn txid txix) =
    TxIn (fromShelleyTxId txid) (TxIx (fromIntegral txix))


-- ----------------------------------------------------------------------------
-- Transaction outputs
--

data TxOut era
  = TxOut (AddressInEra era) (TxOutValue era) (DataHash era)
  deriving Generic

instance IsCardanoEra era => ToJSON (TxOut era) where
  toJSON (TxOut (AddressInEra addrType addr) val _dHash) =
    case addrType of
      ByronAddressInAnyEra ->
        let hexAddr = serialiseToRawBytesHexText addr
        in object [ "address" .= hexAddr
                  , "value" .= toJSON val
                  ]
      ShelleyAddressInEra sbe ->
        case sbe of
          ShelleyBasedEraShelley ->
            let hexAddr = serialiseToRawBytesHexText addr
            in object [ "address" .= hexAddr
                      , "value" .= toJSON val
                      ]
          ShelleyBasedEraAllegra ->
            let hexAddr = serialiseToRawBytesHexText addr
            in object [ "address" .= hexAddr
                      , "value" .= toJSON val
                      ]
          ShelleyBasedEraMary ->
            let hexAddr = serialiseToRawBytesHexText addr
            in object [ "address" .= hexAddr
                      , "value" .= toJSON val
                      ]
          ShelleyBasedEraAlonzo ->
            let hexAddr = serialiseToRawBytesHexText addr
            in object [ "address" .= hexAddr
                      , "value" .= toJSON val
                      , "dataHash" .= Aeson.Null --TODO:JORDAN FILL IN
                      ]


deriving instance Eq   (TxOut era)
deriving instance Show (TxOut era)

toByronTxOut :: TxOut ByronEra -> Maybe Byron.TxOut
toByronTxOut (TxOut (AddressInEra ByronAddressInAnyEra (ByronAddress addr))
                    (TxOutAdaOnly AdaOnlyInByronEra value) _) =
    Byron.TxOut addr <$> toByronLovelace value

toByronTxOut (TxOut (AddressInEra ByronAddressInAnyEra (ByronAddress _))
                    (TxOutValue era _) _) = case era of {}

toByronTxOut (TxOut (AddressInEra (ShelleyAddressInEra era) ShelleyAddress{})
                    _ _) = case era of {}

toShelleyTxOut :: forall era ledgerera.
                 (ShelleyLedgerEra era ~ ledgerera,
                  IsShelleyBasedEra era, Ledger.ShelleyBased ledgerera)
               => TxOut era -> Core.TxOut ledgerera
toShelleyTxOut (TxOut _ (TxOutAdaOnly AdaOnlyInByronEra _) _) =
    case shelleyBasedEra :: ShelleyBasedEra era of {}

toShelleyTxOut (TxOut addr (TxOutAdaOnly AdaOnlyInShelleyEra value) _) =
    Shelley.TxOut (toShelleyAddr addr) (toShelleyLovelace value)

toShelleyTxOut (TxOut addr (TxOutAdaOnly AdaOnlyInAllegraEra value) _) =
    Shelley.TxOut (toShelleyAddr addr) (toShelleyLovelace value)

toShelleyTxOut (TxOut addr (TxOutValue MultiAssetInMaryEra value) _) =
    Shelley.TxOut (toShelleyAddr addr) (toMaryValue value)

toShelleyTxOut (TxOut addr (TxOutValue MultiAssetInAlonzoEra value) dHash) =
    Alonzo.TxOut (toShelleyAddr addr) (toMaryValue value) . maybeToStrictMaybe $ toAlonzoDataHash dHash

fromShelleyTxOut :: Shelley.TxOut StandardShelley -> TxOut ShelleyEra
fromShelleyTxOut txout = fromTxOut ShelleyBasedEraShelley txout SNothing

fromTxOut
  :: ShelleyLedgerEra era ~ ledgerera
  => ShelleyBasedEra era
  -> Core.TxOut ledgerera
  -> StrictMaybe (Alonzo.DataHash ledgerera)
  -> TxOut era
fromTxOut shelleyBasedEra' ledgerTxOut _mDhash =
  case shelleyBasedEra' of
    ShelleyBasedEraShelley -> let (Shelley.TxOut addr value) = ledgerTxOut
                              in TxOut (fromShelleyAddr addr)
                                       (TxOutAdaOnly AdaOnlyInShelleyEra
                                                      (fromShelleyLovelace value))
                                                      DataHashNone

    ShelleyBasedEraAllegra -> let (Shelley.TxOut addr value) = ledgerTxOut
                              in TxOut (fromShelleyAddr addr)
                                       (TxOutAdaOnly AdaOnlyInAllegraEra
                                                     (fromShelleyLovelace value))
                                                     DataHashNone

    ShelleyBasedEraMary    -> let (Shelley.TxOut addr value) = ledgerTxOut
                              in TxOut (fromShelleyAddr addr)
                                       (TxOutValue MultiAssetInMaryEra
                                                     (fromMaryValue value))
                                                     DataHashNone

    ShelleyBasedEraAlonzo  -> let (Alonzo.TxOut addr value mDhash) = ledgerTxOut
                              in TxOut (fromShelleyAddr addr)
                                       (TxOutValue MultiAssetInAlonzoEra
                                                     (fromMaryValue value))
                                                     (fromAlonzoDataHash mDhash)

-- ----------------------------------------------------------------------------
-- Era-dependent transaction body features
--

-- | A representation of whether the era supports multi-asset transactions.
--
-- The Mary and subsequent eras support multi-asset transactions.
--
-- The negation of this is 'OnlyAdaSupportedInEra'.
--
data MultiAssetSupportedInEra era where

     -- | Multi-asset transactions are supported in the 'Mary' era.
     MultiAssetInMaryEra   :: MultiAssetSupportedInEra MaryEra
     MultiAssetInAlonzoEra :: MultiAssetSupportedInEra AlonzoEra

deriving instance Eq   (MultiAssetSupportedInEra era)
deriving instance Show (MultiAssetSupportedInEra era)

instance ToJSON (MultiAssetSupportedInEra era) where
  toJSON = Aeson.String . Text.pack . show

-- | A representation of whether the era supports only ada transactions.
--
-- Prior to the Mary era only ada transactions are supported. Multi-assets are
-- supported from the Mary era onwards.
--
-- This is the negation of 'MultiAssetSupportedInEra'. It exists since we need
-- evidence to be positive.
--
data OnlyAdaSupportedInEra era where

     AdaOnlyInByronEra   :: OnlyAdaSupportedInEra ByronEra
     AdaOnlyInShelleyEra :: OnlyAdaSupportedInEra ShelleyEra
     AdaOnlyInAllegraEra :: OnlyAdaSupportedInEra AllegraEra

deriving instance Eq   (OnlyAdaSupportedInEra era)
deriving instance Show (OnlyAdaSupportedInEra era)

multiAssetSupportedInEra :: CardanoEra era
                         -> Either (OnlyAdaSupportedInEra era)
                                   (MultiAssetSupportedInEra era)
multiAssetSupportedInEra ByronEra   = Left AdaOnlyInByronEra
multiAssetSupportedInEra ShelleyEra = Left AdaOnlyInShelleyEra
multiAssetSupportedInEra AllegraEra = Left AdaOnlyInAllegraEra
multiAssetSupportedInEra MaryEra    = Right MultiAssetInMaryEra
multiAssetSupportedInEra AlonzoEra  = Right MultiAssetInAlonzoEra


-- | A representation of whether the era requires explicitly specified fees in
-- transactions.
--
-- The Byron era tx fees are implicit (as the difference bettween the sum of
-- outputs and sum of inputs), but all later eras the fees are specified in the
-- transaction explicitly.
--
data TxFeesExplicitInEra era where

     TxFeesExplicitInShelleyEra :: TxFeesExplicitInEra ShelleyEra
     TxFeesExplicitInAllegraEra :: TxFeesExplicitInEra AllegraEra
     TxFeesExplicitInMaryEra    :: TxFeesExplicitInEra MaryEra
     TxFeesExplicitInAlonzoEra  :: TxFeesExplicitInEra AlonzoEra

deriving instance Eq   (TxFeesExplicitInEra era)
deriving instance Show (TxFeesExplicitInEra era)

-- | A representation of whether the era requires implicitly specified fees in
-- transactions.
--
-- This is the negation of 'TxFeesExplicitInEra'.
--
data TxFeesImplicitInEra era where
     TxFeesImplicitInByronEra :: TxFeesImplicitInEra ByronEra

deriving instance Eq   (TxFeesImplicitInEra era)
deriving instance Show (TxFeesImplicitInEra era)

txFeesExplicitInEra :: CardanoEra era
                    -> Either (TxFeesImplicitInEra era)
                              (TxFeesExplicitInEra era)
txFeesExplicitInEra ByronEra   = Left  TxFeesImplicitInByronEra
txFeesExplicitInEra ShelleyEra = Right TxFeesExplicitInShelleyEra
txFeesExplicitInEra AllegraEra = Right TxFeesExplicitInAllegraEra
txFeesExplicitInEra MaryEra    = Right TxFeesExplicitInMaryEra
txFeesExplicitInEra AlonzoEra  = Right TxFeesExplicitInAlonzoEra


-- | A representation of whether the era supports transactions with an upper
-- bound on the range of slots in which they are valid.
--
-- The Shelley and subsequent eras support an upper bound on the validity
-- range. In the Shelley era specifically it is actually required. It is
-- optional in later eras.
--
data ValidityUpperBoundSupportedInEra era where

     ValidityUpperBoundInShelleyEra :: ValidityUpperBoundSupportedInEra ShelleyEra
     ValidityUpperBoundInAllegraEra :: ValidityUpperBoundSupportedInEra AllegraEra
     ValidityUpperBoundInMaryEra    :: ValidityUpperBoundSupportedInEra MaryEra
     ValidityUpperBoundInAlonzoEra  :: ValidityUpperBoundSupportedInEra AlonzoEra

deriving instance Eq   (ValidityUpperBoundSupportedInEra era)
deriving instance Show (ValidityUpperBoundSupportedInEra era)

validityUpperBoundSupportedInEra :: CardanoEra era
                                 -> Maybe (ValidityUpperBoundSupportedInEra era)
validityUpperBoundSupportedInEra ByronEra   = Nothing
validityUpperBoundSupportedInEra ShelleyEra = Just ValidityUpperBoundInShelleyEra
validityUpperBoundSupportedInEra AllegraEra = Just ValidityUpperBoundInAllegraEra
validityUpperBoundSupportedInEra MaryEra    = Just ValidityUpperBoundInMaryEra
validityUpperBoundSupportedInEra AlonzoEra  = Just ValidityUpperBoundInAlonzoEra


-- | A representation of whether the era supports transactions having /no/
-- upper bound on the range of slots in which they are valid.
--
-- Note that the 'ShelleyEra' /does not support/ omitting a validity upper
-- bound. It was introduced as a /required/ field in Shelley and then made
-- optional in Allegra and subsequent eras.
--
-- The Byron era supports this by virtue of the fact that it does not support
-- validity ranges at all.
--
data ValidityNoUpperBoundSupportedInEra era where

     ValidityNoUpperBoundInByronEra   :: ValidityNoUpperBoundSupportedInEra ByronEra
     ValidityNoUpperBoundInAllegraEra :: ValidityNoUpperBoundSupportedInEra AllegraEra
     ValidityNoUpperBoundInMaryEra    :: ValidityNoUpperBoundSupportedInEra MaryEra
     ValidityNoUpperBoundInAlonzoEra  :: ValidityNoUpperBoundSupportedInEra AlonzoEra

deriving instance Eq   (ValidityNoUpperBoundSupportedInEra era)
deriving instance Show (ValidityNoUpperBoundSupportedInEra era)

validityNoUpperBoundSupportedInEra :: CardanoEra era
                                   -> Maybe (ValidityNoUpperBoundSupportedInEra era)
validityNoUpperBoundSupportedInEra ByronEra   = Just ValidityNoUpperBoundInByronEra
validityNoUpperBoundSupportedInEra ShelleyEra = Nothing
validityNoUpperBoundSupportedInEra AllegraEra = Just ValidityNoUpperBoundInAllegraEra
validityNoUpperBoundSupportedInEra MaryEra    = Just ValidityNoUpperBoundInMaryEra
validityNoUpperBoundSupportedInEra AlonzoEra  = Just ValidityNoUpperBoundInAlonzoEra


-- | A representation of whether the era supports transactions with a lower
-- bound on the range of slots in which they are valid.
--
-- The Allegra and subsequent eras support an optional lower bound on the
-- validity range. No equivalent of 'ValidityNoUpperBoundSupportedInEra' is
-- needed since all eras support having no lower bound.
--
data ValidityLowerBoundSupportedInEra era where

     ValidityLowerBoundInAllegraEra :: ValidityLowerBoundSupportedInEra AllegraEra
     ValidityLowerBoundInMaryEra    :: ValidityLowerBoundSupportedInEra MaryEra
     ValidityLowerBoundInAlonzoEra  :: ValidityLowerBoundSupportedInEra AlonzoEra

deriving instance Eq   (ValidityLowerBoundSupportedInEra era)
deriving instance Show (ValidityLowerBoundSupportedInEra era)

validityLowerBoundSupportedInEra :: CardanoEra era
                                 -> Maybe (ValidityLowerBoundSupportedInEra era)
validityLowerBoundSupportedInEra ByronEra   = Nothing
validityLowerBoundSupportedInEra ShelleyEra = Nothing
validityLowerBoundSupportedInEra AllegraEra = Just ValidityLowerBoundInAllegraEra
validityLowerBoundSupportedInEra MaryEra    = Just ValidityLowerBoundInMaryEra
validityLowerBoundSupportedInEra AlonzoEra  = Just ValidityLowerBoundInAlonzoEra


-- | A representation of whether the era supports transaction metadata.
--
-- Transaction metadata is supported from the Shelley era onwards.
--
data TxMetadataSupportedInEra era where

     TxMetadataInShelleyEra :: TxMetadataSupportedInEra ShelleyEra
     TxMetadataInAllegraEra :: TxMetadataSupportedInEra AllegraEra
     TxMetadataInMaryEra    :: TxMetadataSupportedInEra MaryEra
     TxMetadataInAlonzoEra  :: TxMetadataSupportedInEra AlonzoEra

deriving instance Eq   (TxMetadataSupportedInEra era)
deriving instance Show (TxMetadataSupportedInEra era)

txMetadataSupportedInEra :: CardanoEra era
                         -> Maybe (TxMetadataSupportedInEra era)
txMetadataSupportedInEra ByronEra   = Nothing
txMetadataSupportedInEra ShelleyEra = Just TxMetadataInShelleyEra
txMetadataSupportedInEra AllegraEra = Just TxMetadataInAllegraEra
txMetadataSupportedInEra MaryEra    = Just TxMetadataInMaryEra
txMetadataSupportedInEra AlonzoEra  = Just TxMetadataInAlonzoEra


-- | A representation of whether the era supports auxiliary scripts in
-- transactions.
--
-- Auxiliary scripts are supported from the Allegra era onwards.
--
data AuxScriptsSupportedInEra era where

     AuxScriptsInAllegraEra :: AuxScriptsSupportedInEra AllegraEra
     AuxScriptsInMaryEra    :: AuxScriptsSupportedInEra MaryEra
     AuxScriptsInAlonzoEra  :: AuxScriptsSupportedInEra AlonzoEra

deriving instance Eq   (AuxScriptsSupportedInEra era)
deriving instance Show (AuxScriptsSupportedInEra era)

auxScriptsSupportedInEra :: CardanoEra era
                         -> Maybe (AuxScriptsSupportedInEra era)
auxScriptsSupportedInEra ByronEra   = Nothing
auxScriptsSupportedInEra ShelleyEra = Nothing
auxScriptsSupportedInEra AllegraEra = Just AuxScriptsInAllegraEra
auxScriptsSupportedInEra MaryEra    = Just AuxScriptsInMaryEra
auxScriptsSupportedInEra AlonzoEra  = Just AuxScriptsInAlonzoEra


-- | A representation of whether the era supports withdrawals from reward
-- accounts.
--
-- The Shelley and subsequent eras support stake addresses, their associated
-- reward accounts and support for withdrawals from them.
--
data WithdrawalsSupportedInEra era where

     WithdrawalsInShelleyEra :: WithdrawalsSupportedInEra ShelleyEra
     WithdrawalsInAllegraEra :: WithdrawalsSupportedInEra AllegraEra
     WithdrawalsInMaryEra    :: WithdrawalsSupportedInEra MaryEra
     WithdrawalsInAlonzoEra  :: WithdrawalsSupportedInEra AlonzoEra

deriving instance Eq   (WithdrawalsSupportedInEra era)
deriving instance Show (WithdrawalsSupportedInEra era)

withdrawalsSupportedInEra :: CardanoEra era
                          -> Maybe (WithdrawalsSupportedInEra era)
withdrawalsSupportedInEra ByronEra   = Nothing
withdrawalsSupportedInEra ShelleyEra = Just WithdrawalsInShelleyEra
withdrawalsSupportedInEra AllegraEra = Just WithdrawalsInAllegraEra
withdrawalsSupportedInEra MaryEra    = Just WithdrawalsInMaryEra
withdrawalsSupportedInEra AlonzoEra  = Just WithdrawalsInAlonzoEra


-- | A representation of whether the era supports 'Certificate's embedded in
-- transactions.
--
-- The Shelley and subsequent eras support such certificates.
--
data CertificatesSupportedInEra era where

     CertificatesInShelleyEra :: CertificatesSupportedInEra ShelleyEra
     CertificatesInAllegraEra :: CertificatesSupportedInEra AllegraEra
     CertificatesInMaryEra    :: CertificatesSupportedInEra MaryEra
     CertificatesInAlonzoEra  :: CertificatesSupportedInEra AlonzoEra

deriving instance Eq   (CertificatesSupportedInEra era)
deriving instance Show (CertificatesSupportedInEra era)

certificatesSupportedInEra :: CardanoEra era
                           -> Maybe (CertificatesSupportedInEra era)
certificatesSupportedInEra ByronEra   = Nothing
certificatesSupportedInEra ShelleyEra = Just CertificatesInShelleyEra
certificatesSupportedInEra AllegraEra = Just CertificatesInAllegraEra
certificatesSupportedInEra MaryEra    = Just CertificatesInMaryEra
certificatesSupportedInEra AlonzoEra  = Just CertificatesInAlonzoEra


-- | A representation of whether the era supports 'UpdateProposal's embedded in
-- transactions.
--
-- The Shelley and subsequent eras support such update proposals. They Byron
-- era has a notion of an update proposal, but it is a standalone chain object
-- and not embedded in a transaction.
--
data UpdateProposalSupportedInEra era where

     UpdateProposalInShelleyEra :: UpdateProposalSupportedInEra ShelleyEra
     UpdateProposalInAllegraEra :: UpdateProposalSupportedInEra AllegraEra
     UpdateProposalInMaryEra    :: UpdateProposalSupportedInEra MaryEra
     UpdateProposalInAlonzoEra  :: UpdateProposalSupportedInEra AlonzoEra

deriving instance Eq   (UpdateProposalSupportedInEra era)
deriving instance Show (UpdateProposalSupportedInEra era)

updateProposalSupportedInEra :: CardanoEra era
                             -> Maybe (UpdateProposalSupportedInEra era)
updateProposalSupportedInEra ByronEra   = Nothing
updateProposalSupportedInEra ShelleyEra = Just UpdateProposalInShelleyEra
updateProposalSupportedInEra AllegraEra = Just UpdateProposalInAllegraEra
updateProposalSupportedInEra MaryEra    = Just UpdateProposalInMaryEra
updateProposalSupportedInEra AlonzoEra  = Just UpdateProposalInAlonzoEra


-- ----------------------------------------------------------------------------
-- Transaction output values (era-dependent)
--

data TxOutValue era where

     TxOutAdaOnly :: OnlyAdaSupportedInEra era -> Lovelace -> TxOutValue era

     TxOutValue   :: MultiAssetSupportedInEra era -> Value -> TxOutValue era

deriving instance Eq   (TxOutValue era)
deriving instance Show (TxOutValue era)
deriving instance Generic (TxOutValue era)

instance ToJSON (TxOutValue era) where
  toJSON (TxOutAdaOnly _ ll) = toJSON ll
  toJSON (TxOutValue _ val) = toJSON val

-- ----------------------------------------------------------------------------
-- Transaction fees
--

data TxFee era where

     TxFeeImplicit :: TxFeesImplicitInEra era -> TxFee era

     TxFeeExplicit :: TxFeesExplicitInEra era -> Lovelace -> TxFee era

deriving instance Eq   (TxFee era)
deriving instance Show (TxFee era)


-- ----------------------------------------------------------------------------
-- Transaction validity range
--

-- | This was formerly known as the TTL.
--
data TxValidityUpperBound era where

     TxValidityNoUpperBound :: ValidityNoUpperBoundSupportedInEra era
                            -> TxValidityUpperBound era

     TxValidityUpperBound   :: ValidityUpperBoundSupportedInEra era
                            -> SlotNo
                            -> TxValidityUpperBound era

deriving instance Eq   (TxValidityUpperBound era)
deriving instance Show (TxValidityUpperBound era)


data TxValidityLowerBound era where

     TxValidityNoLowerBound :: TxValidityLowerBound era

     TxValidityLowerBound   :: ValidityLowerBoundSupportedInEra era
                            -> SlotNo
                            -> TxValidityLowerBound era

deriving instance Eq   (TxValidityLowerBound era)
deriving instance Show (TxValidityLowerBound era)


-- ----------------------------------------------------------------------------
-- Transaction metadata (era-dependent)
--

data TxMetadataInEra era where

     TxMetadataNone  :: TxMetadataInEra era

     TxMetadataInEra :: TxMetadataSupportedInEra era
                     -> TxMetadata
                     -> TxMetadataInEra era

deriving instance Eq   (TxMetadataInEra era)
deriving instance Show (TxMetadataInEra era)


-- ----------------------------------------------------------------------------
-- Auxiliary scripts (era-dependent)
--

data TxAuxScripts era where

     TxAuxScriptsNone :: TxAuxScripts era

     TxAuxScripts     :: AuxScriptsSupportedInEra era
                      -> [ScriptInEra era]
                      -> TxAuxScripts era

deriving instance Eq   (TxAuxScripts era)
deriving instance Show (TxAuxScripts era)


-- ----------------------------------------------------------------------------
-- Withdrawals within transactions (era-dependent)
--

data TxWithdrawals era where

     TxWithdrawalsNone :: TxWithdrawals era

     TxWithdrawals     :: WithdrawalsSupportedInEra era
                       -> [((StakeAddress, Lovelace), WithdrawalsTypeInEra era)]
                       -> TxWithdrawals era

deriving instance Eq   (TxWithdrawals era)
deriving instance Show (TxWithdrawals era)

data WithdrawalsTypeInEra era where
  NoPlutusScriptReward :: WithdrawalsTypeInEra era
  PlutusRewarding      :: PlutusScriptsSupportedInEra era
                       -> Maybe ScriptDatum
                       -> WithdrawalsTypeInEra era

deriving instance Eq   (WithdrawalsTypeInEra era)
deriving instance Show (WithdrawalsTypeInEra era)


-- ----------------------------------------------------------------------------
-- Certificates within transactions (era-dependent)
--

data TxCertificates era where

     TxCertificatesNone :: TxCertificates era

     TxCertificates     :: CertificatesSupportedInEra era
                        -> [(Certificate, CertificateTypeInEra era)]
                        -> TxCertificates era

deriving instance Eq   (TxCertificates era)
deriving instance Show (TxCertificates era)


data CertificateTypeInEra era where
  NoPlutusScriptCert :: CertificateTypeInEra era
  PlutusCertifying   :: PlutusScriptsSupportedInEra era
                     -> Maybe ScriptDatum
                     -> CertificateTypeInEra era

deriving instance Eq   (CertificateTypeInEra era)
deriving instance Show (CertificateTypeInEra era)

-- ----------------------------------------------------------------------------
-- Transaction metadata (era-dependent)
--

data TxUpdateProposal era where

     TxUpdateProposalNone :: TxUpdateProposal era

     TxUpdateProposal     :: UpdateProposalSupportedInEra era
                          -> UpdateProposal
                          -> TxUpdateProposal era

deriving instance Eq   (TxUpdateProposal era)
deriving instance Show (TxUpdateProposal era)


-- ----------------------------------------------------------------------------
-- Value minting within transactions (era-dependent)
--

data TxMintValue era where

     TxMintNone  :: TxMintValue era

     TxMintValue :: MultiAssetSupportedInEra era
                 -> [ScriptWitness WitMisc era]
                 -> Value -> TxMintValue era

deriving instance Eq   (TxMintValue era)
deriving instance Show (TxMintValue era)

-- ----------------------------------------------------------------------------
-- The cost to execute Plutus scripts (era-dependent)
--

data TxExecutionUnits era where
    TxExecutionUnitsNone :: TxExecutionUnits era
    TxExecutionUnits     :: ExecutionUnitsSupportedInEra era
                         -> Word64
                         -- ^ Memory
                         -> Word64
                         -- ^ Steps
                         -> TxExecutionUnits era

deriving instance Show (TxExecutionUnits era)
data ExecutionUnitsSupportedInEra era where

     ExecutionUnitsSupportedInAlonzoEra  :: ExecutionUnitsSupportedInEra AlonzoEra

deriving instance Show (ExecutionUnitsSupportedInEra era)

executionUnitsSupportedInEra :: CardanoEra era -> Maybe (ExecutionUnitsSupportedInEra era)
executionUnitsSupportedInEra ByronEra   = Nothing
executionUnitsSupportedInEra ShelleyEra = Nothing
executionUnitsSupportedInEra AllegraEra = Nothing
executionUnitsSupportedInEra MaryEra    = Nothing
executionUnitsSupportedInEra AlonzoEra  = Just ExecutionUnitsSupportedInAlonzoEra

-- ----------------------------------------------------------------------------
-- Data necessary to create a hash of the script execution data.
--
data TxWitnessPPData era where
    TxWitnessPPDataNone :: TxWitnessPPData era
    TxWitnessPPData     :: ProtocolParameters era
                        -> [RedeemerPointer]
                        -> TxWitnessPPData era

data WitnessPPDataSupportedInEra era where

    WitnessPPDataSupportedInAlonzoEra  :: WitnessPPDataSupportedInEra AlonzoEra

witnessPPDataSupportedInEra :: CardanoEra era -> Maybe (WitnessPPDataSupportedInEra era)
witnessPPDataSupportedInEra ByronEra   = Nothing
witnessPPDataSupportedInEra ShelleyEra = Nothing
witnessPPDataSupportedInEra AllegraEra = Nothing
witnessPPDataSupportedInEra MaryEra    = Nothing
witnessPPDataSupportedInEra AlonzoEra  = Just WitnessPPDataSupportedInAlonzoEra

-- ----------------------------------------------------------------------------
-- DataHash
--
--TODO: JORDAN left off - need to update tests with DataHash
newtype DatumHash = DatumHash () deriving (Show, Eq, Ord)

data DataHash era where
  DataHashNone :: DataHash era
  DataHash     :: DataHashSupportedInEra era -> DatumHash -> DataHash era

deriving instance Eq   (DataHash era)
deriving instance Ord  (DataHash era)
deriving instance Show (DataHash era)

data DataHashSupportedInEra era where
  DataHashSupportedInAlonzoEra :: DataHashSupportedInEra AlonzoEra

deriving instance Eq   (DataHashSupportedInEra era)
deriving instance Ord  (DataHashSupportedInEra era)
deriving instance Show (DataHashSupportedInEra era)

toAlonzoDataHash :: DataHash era -> Maybe (Alonzo.DataHash StandardCrypto)
toAlonzoDataHash DataHashNone = Nothing
toAlonzoDataHash (DataHash DataHashSupportedInAlonzoEra _datum) = Nothing --TODO:JORDAN

fromAlonzoDataHash :: StrictMaybe (Alonzo.DataHash StandardCrypto) -> DataHash era
fromAlonzoDataHash _ = DataHashNone

-- ----------------------------------------------------------------------------
-- Transaction body content
--

data TxBodyContent era =
     TxBodyContent {
       txInsAndWits     :: [(TxIn, WitnessKind WitTxIn era, TxInUsedForFees era)],
       txOuts           :: [TxOut era],
       txFee            :: TxFee era,
       txValidityRange  :: (TxValidityLowerBound era,
                            TxValidityUpperBound era),
       txMetadata       :: TxMetadataInEra era,
       txWithdrawals    :: TxWithdrawals era,
       txCertificates   :: TxCertificates era,
       txUpdateProposal :: TxUpdateProposal era,
       txMintValue      :: TxMintValue era,
       txExecutionUnits :: TxExecutionUnits era,
       txWitnessPPData  :: TxWitnessPPData era
     }


-- ----------------------------------------------------------------------------
-- Transaction bodies
--

data TxBody era where

     ByronTxBody
       :: Annotated Byron.Tx ByteString
       -> TxBody ByronEra

     ShelleyTxBody
       :: ShelleyBasedEra era
       -> Ledger.TxBody (ShelleyLedgerEra era)

          -- The 'Ledger.AuxiliaryData' consists of one or several things,
          -- depending on era:
          -- + transaction metadata  (in Shelley and later)
          -- + auxiliary scripts     (in Allegra and later)
          -- + auxiliary script data (in Allonzo and later)
       -> Maybe (Ledger.AuxiliaryData (ShelleyLedgerEra era))

          -- In the Alonzo era we need to indicate whether the non-native
          --(Plutus or otherwise) scripts are expected to validate.
       -> Maybe Alonzo.IsValidating

       -> TxBody era
     -- The 'ShelleyBasedEra' GADT tells us what era we are in.
     -- The 'ShelleyLedgerEra' type family maps that to the era type from the
     -- ledger lib. The 'Ledger.TxBody' type family maps that to a specific
     -- tx body type, which is different for each Shelley-based era.


-- The GADT in the ShelleyTxBody case requires a custom instance
instance Eq (TxBody era) where
    (==) (ByronTxBody txbodyA)
         (ByronTxBody txbodyB) = txbodyA == txbodyB

    (==) (ShelleyTxBody era txbodyA txmetadataA isValidA)
         (ShelleyTxBody _   txbodyB txmetadataB isValidB) =
         case era of
           ShelleyBasedEraShelley -> txmetadataA == txmetadataB
           ShelleyBasedEraAllegra -> txmetadataA == txmetadataB
           ShelleyBasedEraMary    -> txmetadataA == txmetadataB
           ShelleyBasedEraAlonzo  -> txmetadataA == txmetadataB
      && case era of
           ShelleyBasedEraShelley -> txbodyA == txbodyB
           ShelleyBasedEraAllegra -> txbodyA == txbodyB
           ShelleyBasedEraMary    -> txbodyA == txbodyB
           ShelleyBasedEraAlonzo  -> txbodyA == txbodyB
      && case era of
           ShelleyBasedEraShelley -> isValidA == isValidB
           ShelleyBasedEraAllegra -> isValidA == isValidB
           ShelleyBasedEraMary    -> isValidA == isValidB

           ShelleyBasedEraAlonzo  -> isValidA == isValidB
    (==) ByronTxBody{} (ShelleyTxBody era _ _ _) = case era of {}


-- The GADT in the ShelleyTxBody case requires a custom instance
instance Show (TxBody era) where
    showsPrec p (ByronTxBody txbody) =
      showParen (p >= 11)
        ( showString "ByronTxBody "
        . showsPrec 11 txbody
        )

    showsPrec p (ShelleyTxBody ShelleyBasedEraShelley txbody txmetadata _) =
      showParen (p >= 11)
        ( showString "ShelleyTxBody ShelleyBasedEraShelley "
        . showsPrec 11 txbody
        . showChar ' '
        . showsPrec 11 txmetadata
        )

    showsPrec p (ShelleyTxBody ShelleyBasedEraAllegra txbody txmetadata _) =
      showParen (p >= 11)
        ( showString "ShelleyTxBody ShelleyBasedEraAllegra "
        . showsPrec 11 txbody
        . showChar ' '
        . showsPrec 11 txmetadata
        )

    showsPrec p (ShelleyTxBody ShelleyBasedEraMary txbody txmetadata _) =
      showParen (p >= 11)
        ( showString "ShelleyTxBody ShelleyBasedEraMary "
        . showsPrec 11 txbody
        . showChar ' '
        . showsPrec 11 txmetadata
        )
    showsPrec p (ShelleyTxBody ShelleyBasedEraAlonzo txbody txmetadata isValid) =
      showParen (p >= 11)
        ( showString "ShelleyTxBody ShelleyBasedEraAlonzo "
        . showsPrec 11 txbody
        . showChar ' '
        . showsPrec 11 txmetadata
        . showChar ' '
        . showsPrec 11 isValid
        )

instance HasTypeProxy era => HasTypeProxy (TxBody era) where
    data AsType (TxBody era) = AsTxBody (AsType era)
    proxyToAsType _ = AsTxBody (proxyToAsType (Proxy :: Proxy era))

pattern AsByronTxBody :: AsType (TxBody ByronEra)
pattern AsByronTxBody   = AsTxBody AsByronEra
{-# COMPLETE AsByronTxBody #-}

pattern AsShelleyTxBody :: AsType (TxBody ShelleyEra)
pattern AsShelleyTxBody = AsTxBody AsShelleyEra
{-# COMPLETE AsShelleyTxBody #-}


instance IsCardanoEra era => SerialiseAsCBOR (TxBody era) where

    serialiseToCBOR (ByronTxBody txbody) =
      recoverBytes txbody

    serialiseToCBOR (ShelleyTxBody era txbody txmetadata _isValid) =
      case era of
        -- Use the same serialisation impl, but at different types:
        ShelleyBasedEraShelley -> serialiseShelleyBasedTxBody txbody txmetadata
        ShelleyBasedEraAllegra -> serialiseShelleyBasedTxBody txbody txmetadata
        ShelleyBasedEraMary    -> serialiseShelleyBasedTxBody txbody txmetadata
        ShelleyBasedEraAlonzo  -> error "TODO:Jordan"

    deserialiseFromCBOR _ bs =
      case cardanoEra :: CardanoEra era of
        ByronEra ->
          ByronTxBody <$>
            CBOR.decodeFullAnnotatedBytes
              "Byron TxBody"
              CBOR.fromCBORAnnotated
              (LBS.fromStrict bs)

        -- Use the same derialisation impl, but at different types:
        ShelleyEra ->undefined --TODO:Jordan check out
        -- deserialiseShelleyBasedTxBody
        --                (ShelleyTxBody ShelleyBasedEraShelley) bs
        AllegraEra ->undefined
        -- deserialiseShelleyBasedTxBody
        --                (ShelleyTxBody ShelleyBasedEraAllegra) bs
        MaryEra    ->undefined
        -- deserialiseShelleyBasedTxBody
        --                (ShelleyTxBody ShelleyBasedEraMary) bs
        AlonzoEra  ->undefined
        -- deserialiseShelleyBasedTxBody
        --                (ShelleyTxBody ShelleyBasedEraAlonzo) bs

-- | The serialisation format for the different Shelley-based eras are not the
-- same, but they can be handled generally with one overloaded implementation.
--
serialiseShelleyBasedTxBody :: forall txbody metadata.
                                (ToCBOR txbody, ToCBOR metadata)
                            => txbody -> Maybe metadata -> ByteString
serialiseShelleyBasedTxBody txbody txmetadata =
    CBOR.serializeEncoding' $
        CBOR.encodeListLen 2
     <> CBOR.toCBOR txbody
     <> CBOR.encodeNullMaybe CBOR.toCBOR txmetadata

_deserialiseShelleyBasedTxBody :: forall txbody metadata pair isValidating.
                                (FromCBOR (CBOR.Annotator txbody),
                                 FromCBOR (CBOR.Annotator metadata),
                                 FromCBOR (CBOR.Annotator isValidating))
                              => (txbody -> Maybe metadata -> Maybe isValidating -> pair)
                              -> ByteString
                              -> Either CBOR.DecoderError pair
_deserialiseShelleyBasedTxBody mkTxBody bs =
    CBOR.decodeAnnotator
      "Shelley TxBody"
      decodeAnnotatedPair
      (LBS.fromStrict bs)
  where
    decodeAnnotatedPair :: CBOR.Decoder s (CBOR.Annotator pair)
    decodeAnnotatedPair =  do
      CBOR.decodeListLenOf 3
      txbody       <- fromCBOR
      txmetadata   <- CBOR.decodeNullMaybe fromCBOR
      isValidating <- CBOR.decodeNullMaybe fromCBOR
      return $ CBOR.Annotator $ \fbs ->
        mkTxBody
          (CBOR.runAnnotator txbody fbs)
          (CBOR.runAnnotator <$> txmetadata <*> pure fbs)
          (CBOR.runAnnotator <$> isValidating <*> pure fbs)

instance IsCardanoEra era => HasTextEnvelope (TxBody era) where
    textEnvelopeType _ =
      case cardanoEra :: CardanoEra era of
        ByronEra   -> "TxUnsignedByron"
        ShelleyEra -> "TxUnsignedShelley"
        AllegraEra -> "TxBodyAllegra"
        MaryEra    -> "TxBodyMary"
        AlonzoEra    -> "TxBodyAlonzo"


-- ----------------------------------------------------------------------------
-- Constructing transaction bodies
--

data TxBodyError era =
       TxBodyEmptyTxIns
     | TxBodyEmptyTxOuts
     | TxBodyOutputNegative Quantity (TxOut era)
     | TxBodyOutputOverflow Quantity (TxOut era)
     | TxBodyMetadataError [(Word64, TxMetadataRangeError)]
     | TxBodyMintAdaError
     deriving Show

instance Error (TxBodyError era) where
    displayError TxBodyEmptyTxIns  = "Transaction body has no inputs"
    displayError TxBodyEmptyTxOuts = "Transaction body has no outputs"
    displayError (TxBodyOutputNegative (Quantity q) txout) =
      "Negative quantity (" ++ show q ++ ") in transaction output: " ++
      show txout
    displayError (TxBodyOutputOverflow (Quantity q) txout) =
      "Quantity too large (" ++ show q ++ " >= 2^64) in transaction output: " ++
      show txout
    displayError (TxBodyMetadataError [(k, err)]) =
      "Error in metadata entry " ++ show k ++ ": " ++ displayError err
    displayError (TxBodyMetadataError errs) =
      "Error in metadata entries: " ++
      intercalate "; "
        [ show k ++ ": " ++ displayError err
        | (k, err) <- errs ]
    displayError TxBodyMintAdaError =
      "Transaction cannot mint ada, only non-ada assets"


makeTransactionBody :: forall era.
                       IsCardanoEra era
                    => TxBodyContent era
                    -> Either (TxBodyError era) (TxBody era)
makeTransactionBody =
    case cardanoEraStyle (cardanoEra :: CardanoEra era) of
      LegacyByronEra      -> makeByronTransactionBody
      ShelleyBasedEra era -> makeShelleyTransactionBody era


makeByronTransactionBody :: TxBodyContent ByronEra
                         -> Either (TxBodyError ByronEra) (TxBody ByronEra)
makeByronTransactionBody TxBodyContent { txInsAndWits, txOuts } = do
    ins'  <- NonEmpty.nonEmpty txInsAndWits ?! TxBodyEmptyTxIns
    let ins'' = NonEmpty.map (\(txin,_,_) -> toByronTxIn txin) ins'

    outs'  <- NonEmpty.nonEmpty txOuts    ?! TxBodyEmptyTxOuts
    outs'' <- traverse
                (\out -> toByronTxOut out ?! classifyRangeError out)
                outs'
    return $
      ByronTxBody $
        reAnnotate $
          Annotated
            (Byron.UnsafeTx ins'' outs'' (Byron.mkAttributes ()))
            ()
  where
    classifyRangeError :: TxOut ByronEra -> TxBodyError ByronEra
    classifyRangeError
      txout@(TxOut (AddressInEra ByronAddressInAnyEra ByronAddress{})
                   (TxOutAdaOnly AdaOnlyInByronEra value) _)
      | value < 0        = TxBodyOutputNegative (lovelaceToQuantity value) txout
      | otherwise        = TxBodyOutputOverflow (lovelaceToQuantity value) txout

    classifyRangeError
      (TxOut (AddressInEra ByronAddressInAnyEra (ByronAddress _))
             (TxOutValue era _) _) = case era of {}

    classifyRangeError
      (TxOut (AddressInEra (ShelleyAddressInEra era) ShelleyAddress{})
             _ _) = case era of {}

makeShelleyTransactionBody :: ShelleyBasedEra era
                           -> TxBodyContent era
                           -> Either (TxBodyError era) (TxBody era)
makeShelleyTransactionBody era@ShelleyBasedEraShelley
                           TxBodyContent {
                             txInsAndWits,
                             txOuts,
                             txFee,
                             txValidityRange = (_, upperBound),
                             txMetadata,
                             txWithdrawals,
                             txCertificates,
                             txUpdateProposal
                           } = do
    guard (not (null txInsAndWits)) ?! TxBodyEmptyTxIns
    sequence_
      [ do guard (v >= 0) ?! TxBodyOutputNegative (lovelaceToQuantity v) txout
           guard (v <= maxTxOut) ?! TxBodyOutputOverflow (lovelaceToQuantity v) txout
      | let maxTxOut = fromIntegral (maxBound :: Word64) :: Lovelace
      , txout@(TxOut _ (TxOutAdaOnly AdaOnlyInShelleyEra v) _) <- txOuts ]
    case txMetadata of
      TxMetadataNone      -> return ()
      TxMetadataInEra _ m -> first TxBodyMetadataError (validateTxMetadata m)

    return $
      ShelleyTxBody era
        (Shelley.TxBody
          (Set.fromList [ toShelleyTxIn txin | (txin,_,_) <- txInsAndWits ])
          (Seq.fromList (map toShelleyTxOut txOuts))
          (case txCertificates of
             TxCertificatesNone  -> Seq.empty
             TxCertificates _ cs ->
               Seq.fromList
                 $ map (\(c,_) -> toShelleyCertificate c) cs)
          (case txWithdrawals of
             TxWithdrawalsNone  -> Shelley.Wdrl Map.empty
             TxWithdrawals _ ws -> toShelleyWithdrawal $ map fst ws)
          (case txFee of
             TxFeeImplicit era'  -> case era' of {}
             TxFeeExplicit _ fee -> toShelleyLovelace fee)
          (case upperBound of
             TxValidityNoUpperBound era' -> case era' of {}
             TxValidityUpperBound _ ttl  -> ttl)
          (case txUpdateProposal of
             TxUpdateProposalNone -> SNothing
             TxUpdateProposal _ p -> SJust (toUpdate era p))
          (maybeToStrictMaybe
            (Ledger.hashAuxiliaryData @StandardShelley <$> txAuxData)))
        txAuxData
        Nothing
  where
    txAuxData :: Maybe (Ledger.AuxiliaryData StandardShelley)
    txAuxData
      | Map.null ms = Nothing
      | otherwise   = Just (toShelleyAuxiliaryData ms)
      where
        ms = case txMetadata of
               TxMetadataNone                     -> Map.empty
               TxMetadataInEra _ (TxMetadata ms') -> ms'

makeShelleyTransactionBody era@ShelleyBasedEraAllegra
                           TxBodyContent {
                             txInsAndWits,
                             txOuts,
                             txFee,
                             txValidityRange = (lowerBound, upperBound),
                             txMetadata,
                             txWithdrawals,
                             txCertificates,
                             txUpdateProposal
                           } = do

    guard (not (null txInsAndWits)) ?! TxBodyEmptyTxIns
    sequence_
      [ do guard (v >= 0) ?! TxBodyOutputNegative (lovelaceToQuantity v) txout
           guard (v <= maxTxOut) ?! TxBodyOutputOverflow (lovelaceToQuantity v) txout
      | let maxTxOut = fromIntegral (maxBound :: Word64) :: Lovelace
      , txout@(TxOut _ (TxOutAdaOnly AdaOnlyInAllegraEra v) _) <- txOuts
      ]
    case txMetadata of
      TxMetadataNone      -> return ()
      TxMetadataInEra _ m -> validateTxMetadata m ?!. TxBodyMetadataError

    let txIns = [ txin | (txin,_,_) <- txInsAndWits ]

    return $
      ShelleyTxBody era
        (Allegra.TxBody
          (Set.fromList (map toShelleyTxIn txIns))
          (Seq.fromList (map toShelleyTxOut txOuts))
          (case txCertificates of
             TxCertificatesNone  -> Seq.empty
             TxCertificates _ cs ->
               Seq.fromList $ map (\(c,_) -> toShelleyCertificate c) cs)
          (case txWithdrawals of
             TxWithdrawalsNone  -> Shelley.Wdrl Map.empty
             TxWithdrawals _ ws -> toShelleyWithdrawal $ map fst ws)
          (case txFee of
             TxFeeImplicit era'  -> case era' of {}
             TxFeeExplicit _ fee -> toShelleyLovelace fee)
          (Allegra.ValidityInterval {
             Allegra.invalidBefore    = case lowerBound of
                                          TxValidityNoLowerBound   -> SNothing
                                          TxValidityLowerBound _ s -> SJust s,
             Allegra.invalidHereafter = case upperBound of
                                          TxValidityNoUpperBound _ -> SNothing
                                          TxValidityUpperBound _ s -> SJust s
           })
          (case txUpdateProposal of
             TxUpdateProposalNone -> SNothing
             TxUpdateProposal _ p -> SJust (toUpdate era p))
          (maybeToStrictMaybe
            (Ledger.hashAuxiliaryData @StandardAllegra <$> txAuxData))
          mempty) -- No minting in Allegra, only Mary
        txAuxData
        Nothing
  where
    txAuxData :: Maybe (Ledger.AuxiliaryData StandardAllegra)
    txAuxData
      | Map.null ms
      , null scriptWits   = Nothing
      | otherwise = Just $ toAllegraAuxiliaryData ms scriptWits
      where
        ms = case txMetadata of
               TxMetadataNone                     -> Map.empty
               TxMetadataInEra _ (TxMetadata ms') -> ms'
        scriptWits = [ sWit | (_, WitnessByScript sWit, _ ) <- txInsAndWits ]

makeShelleyTransactionBody era@ShelleyBasedEraMary
                           TxBodyContent {
                             txInsAndWits,
                             txOuts,
                             txFee,
                             txValidityRange = (lowerBound, upperBound),
                             txMetadata,
                             txWithdrawals,
                             txCertificates,
                             txUpdateProposal,
                             txMintValue
                           } = do

    guard (not (null txInsAndWits)) ?! TxBodyEmptyTxIns
    sequence_
      [ do allPositive
           allWithinMaxBound
      | let maxTxOut = fromIntegral (maxBound :: Word64) :: Quantity
      , txout@(TxOut _ (TxOutValue MultiAssetInMaryEra v) _) <- txOuts
      , let allPositive       = case [ q | (_,q) <- valueToList v, q < 0 ] of
                                  []  -> Right ()
                                  q:_ -> Left (TxBodyOutputNegative q txout)
            allWithinMaxBound = case [ q | (_,q) <- valueToList v, q > maxTxOut ] of
                                  []  -> Right ()
                                  q:_ -> Left (TxBodyOutputOverflow q txout)
      ]
    case txMetadata of
      TxMetadataNone      -> return ()
      TxMetadataInEra _ m -> validateTxMetadata m ?!. TxBodyMetadataError
    case txMintValue of
      TxMintNone      -> return ()
      TxMintValue _ _ v -> guard (selectLovelace v == 0) ?! TxBodyMintAdaError

    let txIns = [ txin | (txin,_,_) <- txInsAndWits ]

    return $
      ShelleyTxBody era
        (Allegra.TxBody
          (Set.fromList (map toShelleyTxIn txIns))
          (Seq.fromList (map toShelleyTxOut txOuts))
          (case txCertificates of
             TxCertificatesNone  -> Seq.empty
             TxCertificates _ cs -> Seq.fromList $ map (\(c,_) -> toShelleyCertificate c) cs)
          (case txWithdrawals of
             TxWithdrawalsNone  -> Shelley.Wdrl Map.empty
             TxWithdrawals _ ws -> toShelleyWithdrawal $ map fst ws)
          (case txFee of
             TxFeeImplicit era'  -> case era' of {}
             TxFeeExplicit _ fee -> toShelleyLovelace fee)
          (Allegra.ValidityInterval {
             Allegra.invalidBefore    = case lowerBound of
                                          TxValidityNoLowerBound   -> SNothing
                                          TxValidityLowerBound _ s -> SJust s,
             Allegra.invalidHereafter = case upperBound of
                                          TxValidityNoUpperBound _ -> SNothing
                                          TxValidityUpperBound _ s -> SJust s
           })
          (case txUpdateProposal of
             TxUpdateProposalNone -> SNothing
             TxUpdateProposal _ p -> SJust (toUpdate era p))
          (maybeToStrictMaybe
            (Ledger.hashAuxiliaryData @StandardMary <$> txAuxData))
          (case txMintValue of
             TxMintNone      -> mempty
             TxMintValue _ _ v -> toMaryValue v))
        txAuxData
        Nothing
  where
    txAuxData :: Maybe (Ledger.AuxiliaryData StandardMary)
    txAuxData
      | Map.null ms
      , null scriptWits   = Nothing
      | otherwise = Just $ toAllegraAuxiliaryData ms scriptWits
      where
        ms = case txMetadata of
               TxMetadataNone                     -> Map.empty
               TxMetadataInEra _ (TxMetadata ms') -> ms'
        scriptWits = [ sWit | (_, WitnessByScript sWit, _ ) <- txInsAndWits ]


makeShelleyTransactionBody era@ShelleyBasedEraAlonzo
                           TxBodyContent { txInsAndWits,
                                           txOuts,
                                           txFee,
                                           txValidityRange = (lowerBound, upperBound),
                                           txMetadata,
                                           txWithdrawals,
                                           txCertificates,
                                           txUpdateProposal,
                                           txMintValue,
                                           txExecutionUnits,
                                           txWitnessPPData
                                           -- TODO: Need isValidating here:Jordan
                                          } = do

    guard (not (null txInsAndWits)) ?! TxBodyEmptyTxIns
    sequence_
      [ do allPositive
           allWithinMaxBound
      | let maxTxOut = fromIntegral (maxBound :: Word64) :: Quantity
      , txout@(TxOut _ (TxOutValue MultiAssetInAlonzoEra v) _mDataHash) <- txOuts
      , let allPositive       = case [ q | (_,q) <- valueToList v, q < 0 ] of
                                  []  -> Right ()
                                  q:_ -> Left (TxBodyOutputNegative q txout)
            allWithinMaxBound = case [ q | (_,q) <- valueToList v, q > maxTxOut ] of
                                  []  -> Right ()
                                  q:_ -> Left (TxBodyOutputOverflow q txout)
      ]

    let spendingInputs = [ txin | (txin, _, TxInNotInUseForFees) <- txInsAndWits ]
        plutusFees = [ txIn | (txIn, _, TxInUsedForFees _) <- txInsAndWits ]

    -- TODO: For Alonzo era txbody
    let _txWitnessPPDataHash = makeTxWitnessPPDataHash
                                 PlutusScriptV1InAlonzo
                                 txWitnessPPData
                                 (error "txInsAndWits")
                                 txCertificates
                                 txOuts
                                 txWithdrawals
        _plutusScriptHash = error "txAuxScripts" --TODO: sort and hash
        _executionUnits = show txExecutionUnits

    case txMetadata of
      TxMetadataNone      -> return ()
      TxMetadataInEra _ m -> validateTxMetadata m ?!. TxBodyMetadataError
    case txMintValue of
      TxMintNone      -> return ()
      TxMintValue _ _mPlutScript v -> guard (selectLovelace v == 0) ?! TxBodyMintAdaError

    return $
      ShelleyTxBody era
        (Alonzo.TxBody
          (Set.fromList $ map toShelleyTxIn spendingInputs)
          (Set.fromList $ map toShelleyTxIn plutusFees)
          (Seq.fromList (map toShelleyTxOut txOuts))
          (case txCertificates of
             TxCertificatesNone  -> Seq.empty
             TxCertificates _ cs -> Seq.fromList
                                      $ map (\(c,_mPlutusScripts) -> toShelleyCertificate c) cs) --TODO: Need to handle this
          (case txWithdrawals of
             TxWithdrawalsNone  -> Shelley.Wdrl Map.empty
             TxWithdrawals _ ws -> toShelleyWithdrawal $ map fst ws)
          (case txFee of
             TxFeeImplicit era'  -> case era' of {}
             TxFeeExplicit _ fee -> toShelleyLovelace fee)
          (Allegra.ValidityInterval {
             Allegra.invalidBefore    = case lowerBound of
                                          TxValidityNoLowerBound   -> SNothing
                                          TxValidityLowerBound _ s -> SJust s,
             Allegra.invalidHereafter = case upperBound of
                                          TxValidityNoUpperBound _ -> SNothing
                                          TxValidityUpperBound _ s -> SJust s
           })
          (case txUpdateProposal of
             TxUpdateProposalNone -> SNothing
             TxUpdateProposal _ p -> SJust (toUpdate era p))
          (case txMintValue of
             TxMintNone      -> mempty
             TxMintValue _ _ v -> toMaryValue v)
          (maybeToStrictMaybe Nothing)
          (maybeToStrictMaybe $ hashedTxAuxData txAuxData)
        )
        txAuxData
        Nothing --TODO: Jordan
  where
   hashedTxAuxData :: Maybe (Alonzo.AuxiliaryData (Alonzo.AlonzoEra StandardCrypto))
                   -> Maybe (Alonzo.AuxiliaryDataHash StandardCrypto)
   hashedTxAuxData mAuxData = SafeHash.hashAnnotated <$> mAuxData

   txAuxData :: Maybe (Ledger.AuxiliaryData (Alonzo.AlonzoEra StandardCrypto))
   txAuxData
     | Map.null ms
     , null scriptWits = Nothing
     | otherwise = Just (toAlonzoAuxiliaryData ms scriptWits [])--TODO:Jordan include plutus data!
     where
       ms = case txMetadata of
              TxMetadataNone                     -> Map.empty
              TxMetadataInEra _ (TxMetadata ms') -> ms'

       scriptWits = [ sWit | (_, WitnessByScript sWit,_) <- txInsAndWits ]

toShelleyWithdrawal :: [(StakeAddress, Lovelace)] -> Shelley.Wdrl StandardCrypto
toShelleyWithdrawal withdrawals =
    Shelley.Wdrl $
      Map.fromList
        [ (toShelleyStakeAddr stakeAddr, toShelleyLovelace value)
        | (stakeAddr, value) <- withdrawals ]

-- | In the Shelley era the auxiliary data consists only of the tx metadata
toShelleyAuxiliaryData :: Map Word64 TxMetadataValue
                       -> Ledger.AuxiliaryData StandardShelley
toShelleyAuxiliaryData m =
    Shelley.Metadata
      (toShelleyMetadata m)

-- | In the Allegra and Mary eras the auxiliary data consists of the tx metadata
-- and the axiliary scripts.
--
toAllegraAuxiliaryData :: forall era ledgerera witctx.
                          ShelleyLedgerEra era ~ ledgerera
                       => Ledger.AuxiliaryData ledgerera ~ Allegra.AuxiliaryData ledgerera
                       => Ledger.AnnotatedData (Ledger.Script ledgerera)
                       => Ord (Ledger.Script ledgerera)
                       => Map Word64 TxMetadataValue
                       -> [ScriptWitness witctx era]
                       -> Ledger.AuxiliaryData ledgerera
toAllegraAuxiliaryData m ss =
  let scripts = mapMaybe toShelleyScript' ss
  in Allegra.AuxiliaryData
      (toShelleyMetadata m)
      (Seq.fromList scripts)

toAlonzoAuxiliaryData
  :: forall era ledgerera witctx.
     ShelleyLedgerEra era ~ ledgerera
  => Ledger.AuxiliaryData ledgerera ~ Alonzo.AuxiliaryData ledgerera
  => Ledger.Era ledgerera
  => ToCBOR (Ledger.Script ledgerera)
  => Ord (Ledger.Script ledgerera)
  => Map Word64 TxMetadataValue
  -> [ScriptWitness witctx era]
  -> [Alonzo.Data ledgerera]
  -> Ledger.AuxiliaryData ledgerera
toAlonzoAuxiliaryData m ss plutusData =
    let scripts = mapMaybe toShelleyScript' ss
    in Alonzo.AuxiliaryData
        (Set.fromList scripts)
        (Set.fromList plutusData)
        (Set.singleton $ Shelley.Metadata $ toShelleyMetadata m)

-- ----------------------------------------------------------------------------
-- Transitional utility functions for making transaction bodies
--

-- | Transitional function to help the CLI move to the updated TxBody API.
--
makeByronTransaction :: [TxIn]
                     -> [TxOut ByronEra]
                     -> Either (TxBodyError ByronEra) (TxBody ByronEra)
makeByronTransaction txIns txOuts =
    makeTransactionBody $
      TxBodyContent {
        txInsAndWits     = zip3 txIns (repeat WitnessByKey) (repeat TxInNotInUseForFees),
        txOuts,
        txFee            = TxFeeImplicit TxFeesImplicitInByronEra,
        txValidityRange  = (TxValidityNoLowerBound,
                            TxValidityNoUpperBound
                              ValidityNoUpperBoundInByronEra),
        txMetadata       = TxMetadataNone,
        txWithdrawals    = TxWithdrawalsNone,
        txCertificates   = TxCertificatesNone,
        txUpdateProposal = TxUpdateProposalNone,
        txMintValue      = TxMintNone,
        txExecutionUnits = TxExecutionUnitsNone,
        txWitnessPPData  = TxWitnessPPDataNone
      }

-- | Transitional function to help the CLI move to the updated TxBody API.
--
makeShelleyTransaction :: [(TxIn, WitnessKind WitTxIn ShelleyEra, TxInUsedForFees ShelleyEra)]
                       -> [TxOut ShelleyEra]
                       -> SlotNo
                       -> Lovelace
                       -> [(Certificate, CertificateTypeInEra ShelleyEra)]
                       -> [(StakeAddress, Lovelace)]
                       -> Maybe TxMetadata
                       -> Maybe UpdateProposal
                       -> Either (TxBodyError ShelleyEra) (TxBody ShelleyEra)
makeShelleyTransaction txInsAndWits txOuts ttl fee
                       certs withdrawals mMetadata mUpdateProp =
    makeTransactionBody $
      TxBodyContent {
        txInsAndWits,
        txOuts,
        txFee            = TxFeeExplicit TxFeesExplicitInShelleyEra fee,
        txValidityRange  = (TxValidityNoLowerBound,
                            TxValidityUpperBound
                              ValidityUpperBoundInShelleyEra ttl),
        txMetadata       = case mMetadata of
                             Nothing -> TxMetadataNone
                             Just md -> TxMetadataInEra
                                          TxMetadataInShelleyEra md,
        txWithdrawals    = TxWithdrawals WithdrawalsInShelleyEra $ map (\(s,l) -> ((s, l), NoPlutusScriptReward)) withdrawals,
        txCertificates   = TxCertificates CertificatesInShelleyEra certs,
        txUpdateProposal = case mUpdateProp of
                             Nothing -> TxUpdateProposalNone
                             Just up -> TxUpdateProposal
                                          UpdateProposalInShelleyEra up,
        txMintValue      = TxMintNone,
        txExecutionUnits = TxExecutionUnitsNone,
        txWitnessPPData  = TxWitnessPPDataNone
      }


-- ----------------------------------------------------------------------------
-- Other utilities helpful with making transaction bodies
--

-- | Compute the 'TxIn' of the initial UTxO pseudo-transaction corresponding
-- to the given address in the genesis initial funds.
--
-- The Shelley initial UTxO is constructed from the 'sgInitialFunds' which
-- is not a full UTxO but just a map from addresses to coin values.
--
-- This gets turned into a UTxO by making a pseudo-transaction for each address,
-- with the 0th output being the coin value. So to spend from the initial UTxO
-- we need this same 'TxIn' to use as an input to the spending transaction.
--
genesisUTxOPseudoTxIn :: NetworkId -> Hash GenesisUTxOKey -> TxIn
genesisUTxOPseudoTxIn nw (GenesisUTxOKeyHash kh) =
    --TODO: should handle Byron UTxO case too.
    fromShelleyTxIn (Shelley.initialFundsPseudoTxIn addr)
  where
    addr :: Shelley.Addr StandardCrypto
    addr = Shelley.Addr
             (toShelleyNetwork nw)
             (Shelley.KeyHashObj kh)
             Shelley.StakeRefNull

{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- | The various Cardano protocol parameters, including:
--
-- * the current values of updateable protocol parameters: 'ProtocolParameters'
-- * updates to protocol parameters: 'ProtocolParametersUpdate'
-- * update proposals that can be embedded in transactions: 'UpdateProposal'
-- * parameters fixed in the genesis file: 'GenesisParameters'
--
module Cardano.Api.ProtocolParameters (
    -- * The updateable protocol paramaters
    ProtocolParameters(..),
    EpochNo,

    -- * Updates to the protocol paramaters
    ProtocolParametersUpdate(..),

    -- * PraosNonce
    PraosNonce,
    makePraosNonce,

    -- * Update proposals to change the protocol paramaters
    UpdateProposal(..),
    makeShelleyUpdateProposal,

    -- * Protocol paramaters fixed in the genesis file
    GenesisParameters(..),
    EpochSize(..),

    -- * Internal conversion functions
    toShelleyPParamsUpdate,
    toShelleyProposedPPUpdates,
    toShelleyUpdate,
    toUpdate,
    fromShelleyPParams,
    fromShelleyPParamsUpdate,
    fromShelleyProposedPPUpdates,
    fromShelleyUpdate,
    fromShelleyGenesis,

    -- * Data family instances
    AsType(..)
  ) where

import           Prelude

import           Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, withText, (.:), (.=))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import           Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy.Char8 as LBS
import           Data.Map.Strict (Map, empty)
import qualified Data.Map.Strict as Map
import           Data.Scientific (Scientific)
import qualified Data.Text as Text
import           Data.Time (NominalDiffTime, UTCTime)
import           Data.Word (Word64)
import           GHC.Generics
import           Numeric.Natural

import           Control.Monad

import qualified Cardano.Binary as CBOR
import qualified Cardano.Crypto.Hash.Class as Crypto
import           Cardano.Slotting.Slot (EpochNo, EpochSize (..))

import qualified Cardano.Ledger.Era as Ledger
import qualified Cardano.Ledger.Shelley.Constraints as Shelley
import           Ouroboros.Consensus.Shelley.Eras (StandardShelley)
import           Ouroboros.Consensus.Shelley.Protocol.Crypto (StandardCrypto)

import qualified Cardano.Ledger.Alonzo.PParams as Alonzo
import           Shelley.Spec.Ledger.BaseTypes (maybeToStrictMaybe, strictMaybeToMaybe)
import qualified Shelley.Spec.Ledger.BaseTypes as Shelley
import qualified Shelley.Spec.Ledger.Genesis as Shelley
import qualified Shelley.Spec.Ledger.Keys as Shelley
import qualified Shelley.Spec.Ledger.PParams as Shelley

import           Cardano.Api.Address
import           Cardano.Api.Eras
import           Cardano.Api.HasTypeProxy
import           Cardano.Api.Hash
import           Cardano.Api.KeysByron
import           Cardano.Api.KeysShelley
import           Cardano.Api.NetworkId
import           Cardano.Api.Script
import           Cardano.Api.SerialiseCBOR
import           Cardano.Api.SerialiseTextEnvelope
import           Cardano.Api.StakePoolMetadata
import           Cardano.Api.TxMetadata
import           Cardano.Api.Value


-- | The values of the set of /updateable/ protocol paramaters. At any
-- particular point on the chain there is a current set of paramaters in use.
--
-- These paramaters can be updated (at epoch boundaries) via an
-- 'UpdateProposal', which contains a 'ProtocolParametersUpdate'.
--
-- The 'ProtocolParametersUpdate' is essentially a diff for the
-- 'ProtocolParameters'.
--
-- There are also paramaters fixed in the Genesis file. See 'GenesisParameters'.
--
data ProtocolParameters era =
     ProtocolParameters {

       -- | Protocol version, major and minor. Updating the major version is
       -- used to trigger hard forks.
       --
       protocolParamProtocolVersion :: (Natural, Natural),

       -- | The decentralization parameter. This is fraction of slots that
       -- belong to the BFT overlay schedule, rather than the Praos schedule.
       -- So 1 means fully centralised, while 0 means fully decentralised.
       --
       -- This is the \"d\" parameter from the design document.
       --
       protocolParamDecentralization :: Rational,

       -- | Extra entropy for the Praos per-epoch nonce.
       --
       -- This can be used to add extra entropy during the decentralisation
       -- process. If the extra entropy can be demonstrated to be generated
       -- randomly then this method can be used to show that the initial
       -- federated operators did not subtly bias the initial schedule so that
       -- they retain undue influence after decentralisation.
       --
       protocolParamExtraPraosEntropy :: Maybe PraosNonce,

       -- | The maximum permitted size of a block header.
       --
       -- This must be at least as big as the largest legitimate block headers
       -- but should not be too much larger, to help prevent DoS attacks.
       --
       -- Caution: setting this to be smaller than legitimate block headers is
       -- a sure way to brick the system!
       --
       protocolParamMaxBlockHeaderSize :: Natural,

       -- | The maximum permitted size of the block body (that is, the block
       -- payload, without the block header).
       --
       -- This should be picked with the Praos network delta security parameter
       -- in mind. Making this too large can severely weaken the Praos
       -- consensus properties.
       --
       -- Caution: setting this to be smaller than a transaction that can
       -- change the protocol parameters is a sure way to brick the system!
       --
       protocolParamMaxBlockBodySize :: Natural,

       -- | The maximum permitted size of a transaction.
       --
       -- Typically this should not be too high a fraction of the block size,
       -- otherwise wastage from block fragmentation becomes a problem, and
       -- the current implementation does not use any sophisticated box packing
       -- algorithm.
       --
       protocolParamMaxTxSize :: Natural,

       -- | The constant factor for the minimum fee calculation.
       --
       protocolParamTxFeeFixed :: Natural,

       -- | The linear factor for the minimum fee calculation.
       --
       protocolParamTxFeePerByte :: Natural,

       -- | The minimum permitted value for new UTxO entries, ie for
       -- transaction outputs.
       --
       protocolParamMinUTxOValue :: Maybe Lovelace,

       -- | The deposit required to register a stake address.
       --
       protocolParamStakeAddressDeposit :: Lovelace,

       -- | The deposit required to register a stake pool.
       --
       protocolParamStakePoolDeposit :: Lovelace,

       -- | The minimum value that stake pools are permitted to declare for
       -- their cost parameter.
       --
       protocolParamMinPoolCost :: Lovelace,

       -- | The maximum number of epochs into the future that stake pools
       -- are permitted to schedule a retirement.
       --
       protocolParamPoolRetireMaxEpoch :: EpochNo,

       -- | The equilibrium target number of stake pools.
       --
       -- This is the \"k\" incentives parameter from the design document.
       --
       protocolParamStakePoolTargetNum :: Natural,

       -- | The influence of the pledge in stake pool rewards.
       --
       -- This is the \"a_0\" incentives parameter from the design document.
       --
       protocolParamPoolPledgeInfluence :: Rational,

       -- | The monetary expansion rate. This determines the fraction of the
       -- reserves that are added to the fee pot each epoch.
       --
       -- This is the \"rho\" incentives parameter from the design document.
       --
       protocolParamMonetaryExpansion :: Rational,

       -- | The fraction of the fee pot each epoch that goes to the treasury.
       --
       -- This is the \"tau\" incentives parameter from the design document.
       --
       protocolParamTreasuryCut :: Rational,

       -- | Cost in ada per byte of UTxO storage (instead of
       --protocolParamMinUTxOValue in the Alonzo era onwards).
       protocolParamUTxOCostPerByte :: Maybe Lovelace,

       -- | Cost models for non-native script languages.
       protocolParamCostModels :: Maybe CostModel,

       -- | Prices of execution units (for non-native script languages).
       protocolParamPrices :: Maybe Prices,

       -- | Max total script execution resources units allowed per tx
       protocolParamMaxTxExUnits :: Maybe MaxTxExecutionUnits,

       -- | Max total script execution resources units allowed per block
       protocolParamMaxBlockExUnits :: Maybe MaxBlockExecutionUnits
    }
  deriving (Eq, Generic, Show)

newtype MaxTxExecutionUnits =
    MaxTxExecutionUnits { unMaxTxExecutionUnits :: ExecutionUnits}
    deriving (Eq, Show)

instance ToJSON MaxTxExecutionUnits where
  toJSON (MaxTxExecutionUnits (ExecutionUnits space time)) =
    object [ "maxTxExecutionUnits" .=
                object ["space" .= space, "time" .= time]
           ]

instance FromJSON MaxTxExecutionUnits where
  parseJSON = withObject "MaxTxExecutionUnits" $ \o -> do
    obj <- o .: "maxTxExecutionUnits"
    MaxTxExecutionUnits
      <$> (ExecutionUnits <$> obj .: "space" <*> obj .: "time")

newtype MaxBlockExecutionUnits =
    MaxBlockExecutionUnits { unMaxBlockExecutionUnits :: ExecutionUnits}
    deriving (Eq, Show)

instance ToJSON MaxBlockExecutionUnits where
  toJSON (MaxBlockExecutionUnits (ExecutionUnits space time)) =
    object [ "maxBlockExecutionUnits" .=
                object ["space" .= space, "time" .= time]
           ]

instance FromJSON MaxBlockExecutionUnits where
  parseJSON = withObject "MaxBlockExecutionUnits" $ \o -> do
    obj <- o .: "maxBlockExecutionUnits"
    MaxBlockExecutionUnits
      <$> (ExecutionUnits <$> obj .: "space" <*> obj .: "time")

data ExecutionUnits
    = ExecutionUnits { space :: Word64
                     , time :: Word64
                     } deriving (Eq, Show)


newtype CostModel = CostModel (Map AnyScriptLanguage Cost)
                  deriving (Eq,Show)

newtype Cost = Cost (Map.Map Operation Integer)
             deriving (Eq, Show)

data Operation = Add | Subtract | OtherOperation
                 deriving (Eq, Ord, Show)

instance ToJSON Operation where
  toJSON Add = Aeson.String "Add"
  toJSON Subtract = Aeson.String "Subtract"
  toJSON OtherOperation = Aeson.String "OtherOperation"

instance FromJSON Operation where
  parseJSON = withText "Operation" $ \t ->
                case t of
                  "Add" -> return Add
                  "Subtract" -> return Subtract
                  "OtherOperation" -> return OtherOperation
                  unOp -> fail $ "Unknown operation: " <> Text.unpack unOp

instance ToJSON Cost where
  toJSON (Cost c) = toJSON c

instance Aeson.ToJSONKey Operation where
  toJSONKey = Aeson.toJSONKeyText render
    where
      render = Text.pack . show

instance FromJSON Cost where
  parseJSON = withObject "Cost" $ \obj -> do
   addCost <- obj .: "Add"
   subtractCost <- obj .: "Subtract"
   otherOperationCost <- obj .: "OtherOperation"
   return . Cost $ Map.fromList [ (Add, addCost)
                                , (Subtract, subtractCost)
                                , (OtherOperation, otherOperationCost)
                                ]

instance ToJSON CostModel where
  toJSON (CostModel map') =
    object . concatMap toPair $ Map.toList map'
      where
        toPair :: (AnyScriptLanguage, Cost) -> [Aeson.Pair]
        toPair (AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV1), c) = ["PlutusScriptV1" .= toJSON c]
        toPair (AnyScriptLanguage uLang, _) = error $ "Unsupported script language:" <> show uLang

instance FromJSON CostModel where
  parseJSON = withObject "CostModel" $ \o -> do
    val <- o .: "PlutusScriptV1"
    c <- (parseJSON val :: Aeson.Parser Cost)
    return . CostModel . Map.fromList $ [(AnyScriptLanguage (PlutusScriptLanguage PlutusScriptV1), c)]



data Prices = Prices { perUnitSpace :: Lovelace
                     , perUnitTime :: Lovelace
                     }
            deriving (Eq, Show)

instance FromJSON Prices where
  parseJSON = withObject "Prices" $ \o -> do
    obj <- o .: "prices"
    Prices <$> obj .: "unitSpace" <*> obj .: "unitTime"

instance ToJSON Prices where
  toJSON (Prices perSpace perTime) =
    object [ "prices" .= object
             [ "unitSpace" .= perSpace , "unitTime" .= perTime]
           ]

instance IsCardanoEra era => FromJSON (ProtocolParameters era) where
  parseJSON = parseProtocolParameters cardanoEra



parseProtocolParameters :: CardanoEra era -> Aeson.Value -> Aeson.Parser (ProtocolParameters era)
parseProtocolParameters ByronEra = \_v -> fail "Protocol parameters are not supported in the Byron era."
parseProtocolParameters ShelleyEra =
         withObject "ProtocolParameters" $ \o -> do
                v <- o .: "protocolVersion"
                ProtocolParameters
                        <$> ((,) <$> v .: "major" <*> v .: "minor")
                        <*> o .: "decentralization"
                        <*> o .: "extraPraosEntropy"
                        <*> o .: "maxBlockHeaderSize"
                        <*> o .: "maxBlockBodySize"
                        <*> o .: "maxTxSize"
                        <*> o .: "txFeeFixed"
                        <*> o .: "txFeePerByte"
                        <*> o .: "minUTxOValue"
                        <*> o .: "stakeAddressDeposit"
                        <*> o .: "stakePoolDeposit"
                        <*> o .: "minPoolCost"
                        <*> o .: "poolRetireMaxEpoch"
                        <*> o .: "stakePoolTargetNum"
                        <*> o .: "poolPledgeInfluence"
                        <*> o .: "monetaryExpansion"
                        <*> o .: "treasuryCut"
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing

parseProtocolParameters AllegraEra =
         withObject "ProtocolParameters" $ \o -> do
                v <- o .: "protocolVersion"
                ProtocolParameters
                        <$> ((,) <$> v .: "major" <*> v .: "minor")
                        <*> o .: "decentralization"
                        <*> o .: "extraPraosEntropy"
                        <*> o .: "maxBlockHeaderSize"
                        <*> o .: "maxBlockBodySize"
                        <*> o .: "maxTxSize"
                        <*> o .: "txFeeFixed"
                        <*> o .: "txFeePerByte"
                        <*> o .: "minUTxOValue"
                        <*> o .: "stakeAddressDeposit"
                        <*> o .: "stakePoolDeposit"
                        <*> o .: "minPoolCost"
                        <*> o .: "poolRetireMaxEpoch"
                        <*> o .: "stakePoolTargetNum"
                        <*> o .: "poolPledgeInfluence"
                        <*> o .: "monetaryExpansion"
                        <*> o .: "treasuryCut"
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing

parseProtocolParameters MaryEra =
         withObject "ProtocolParameters" $ \o -> do
                v <- o .: "protocolVersion"
                ProtocolParameters
                        <$> ((,) <$> v .: "major" <*> v .: "minor")
                        <*> o .: "decentralization"
                        <*> o .: "extraPraosEntropy"
                        <*> o .: "maxBlockHeaderSize"
                        <*> o .: "maxBlockBodySize"
                        <*> o .: "maxTxSize"
                        <*> o .: "txFeeFixed"
                        <*> o .: "txFeePerByte"
                        <*> o .: "minUTxOValue"
                        <*> o .: "stakeAddressDeposit"
                        <*> o .: "stakePoolDeposit"
                        <*> o .: "minPoolCost"
                        <*> o .: "poolRetireMaxEpoch"
                        <*> o .: "stakePoolTargetNum"
                        <*> o .: "poolPledgeInfluence"
                        <*> o .: "monetaryExpansion"
                        <*> o .: "treasuryCut"
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing
                        <*> return Nothing

parseProtocolParameters AlonzoEra =
         withObject "ProtocolParameters" $ \o -> do
                v <- o .: "protocolVersion"
                ProtocolParameters
                        <$> ((,) <$> v .: "major" <*> v .: "minor")
                        <*> o .: "decentralization"
                        <*> o .: "extraPraosEntropy"
                        <*> o .: "maxBlockHeaderSize"
                        <*> o .: "maxBlockBodySize"
                        <*> o .: "maxTxSize"
                        <*> o .: "txFeeFixed"
                        <*> o .: "txFeePerByte"
                        <*> o .: "minUTxOValue"
                        <*> o .: "stakeAddressDeposit"
                        <*> o .: "stakePoolDeposit"
                        <*> o .: "minPoolCost"
                        <*> o .: "poolRetireMaxEpoch"
                        <*> o .: "stakePoolTargetNum"
                        <*> o .: "poolPledgeInfluence"
                        <*> o .: "monetaryExpansion"
                        <*> o .: "treasuryCut"
                        <*> o .: "utxoCostPerByte"
                        <*> o .: "costModel"
                        <*> o .: "prices"
                        <*> o .: "maxTxExecUnits"
                        <*> o .: "maxBlockExecUnits"


instance IsCardanoEra era => ToJSON (ProtocolParameters era) where
  toJSON pp =
    case cardanoEra :: CardanoEra era of
      ByronEra -> error "NO PPARAMS"
      ShelleyEra ->
        object [ "extraPraosEntropy" .= protocolParamExtraPraosEntropy pp
               , "stakePoolTargetNum" .= protocolParamStakePoolTargetNum pp
               , "poolRetireMaxEpoch" .= protocolParamPoolRetireMaxEpoch pp
               , "decentralization" .= (fromRational $ protocolParamDecentralization pp :: Scientific)
               , "stakePoolDeposit" .= protocolParamStakePoolDeposit pp
               , "maxBlockHeaderSize" .= protocolParamMaxBlockHeaderSize pp
               , "maxBlockBodySize" .= protocolParamMaxBlockBodySize pp
               , "maxTxSize" .= protocolParamMaxTxSize pp
               , "treasuryCut" .= (fromRational $ protocolParamTreasuryCut pp :: Scientific)
               , "minPoolCost" .= protocolParamMinPoolCost pp
               , "monetaryExpansion" .= (fromRational $ protocolParamMonetaryExpansion pp :: Scientific)
               , "stakeAddressDeposit" .= protocolParamStakeAddressDeposit pp
               , "poolPledgeInfluence" .= (fromRational $ protocolParamPoolPledgeInfluence pp :: Scientific)
               , "protocolVersion" .= let (major, minor) = protocolParamProtocolVersion pp
                                      in object ["major" .= major, "minor" .= minor]
               , "txFeeFixed" .= protocolParamTxFeeFixed pp
               , "txFeePerByte" .= protocolParamTxFeePerByte pp
               , "minUTxOValue"  .= protocolParamMinUTxOValue pp
               ]
      AllegraEra ->
        object [ "extraPraosEntropy" .= protocolParamExtraPraosEntropy pp
               , "stakePoolTargetNum" .= protocolParamStakePoolTargetNum pp
               , "poolRetireMaxEpoch" .= protocolParamPoolRetireMaxEpoch pp
               , "decentralization" .= (fromRational $ protocolParamDecentralization pp :: Scientific)
               , "stakePoolDeposit" .= protocolParamStakePoolDeposit pp
               , "maxBlockHeaderSize" .= protocolParamMaxBlockHeaderSize pp
               , "maxBlockBodySize" .= protocolParamMaxBlockBodySize pp
               , "maxTxSize" .= protocolParamMaxTxSize pp
               , "treasuryCut" .= (fromRational $ protocolParamTreasuryCut pp :: Scientific)
               , "minPoolCost" .= protocolParamMinPoolCost pp
               , "monetaryExpansion" .= (fromRational $ protocolParamMonetaryExpansion pp :: Scientific)
               , "stakeAddressDeposit" .= protocolParamStakeAddressDeposit pp
               , "poolPledgeInfluence" .= (fromRational $ protocolParamPoolPledgeInfluence pp :: Scientific)
               , "protocolVersion" .= let (major, minor) = protocolParamProtocolVersion pp
                                      in object ["major" .= major, "minor" .= minor]
               , "txFeeFixed" .= protocolParamTxFeeFixed pp
               , "txFeePerByte" .= protocolParamTxFeePerByte pp
               , "minUTxOValue"  .= protocolParamMinUTxOValue pp
               ]
      MaryEra ->
        object [ "extraPraosEntropy" .= protocolParamExtraPraosEntropy pp
               , "stakePoolTargetNum" .= protocolParamStakePoolTargetNum pp
               , "poolRetireMaxEpoch" .= protocolParamPoolRetireMaxEpoch pp
               , "decentralization" .= (fromRational $ protocolParamDecentralization pp :: Scientific)
               , "stakePoolDeposit" .= protocolParamStakePoolDeposit pp
               , "maxBlockHeaderSize" .= protocolParamMaxBlockHeaderSize pp
               , "maxBlockBodySize" .= protocolParamMaxBlockBodySize pp
               , "maxTxSize" .= protocolParamMaxTxSize pp
               , "treasuryCut" .= (fromRational $ protocolParamTreasuryCut pp :: Scientific)
               , "minPoolCost" .= protocolParamMinPoolCost pp
               , "monetaryExpansion" .= (fromRational $ protocolParamMonetaryExpansion pp :: Scientific)
               , "stakeAddressDeposit" .= protocolParamStakeAddressDeposit pp
               , "poolPledgeInfluence" .= (fromRational $ protocolParamPoolPledgeInfluence pp :: Scientific)
               , "protocolVersion" .= let (major, minor) = protocolParamProtocolVersion pp
                                      in object ["major" .= major, "minor" .= minor]
               , "txFeeFixed" .= protocolParamTxFeeFixed pp
               , "txFeePerByte" .= protocolParamTxFeePerByte pp
               , "minUTxOValue"  .= protocolParamMinUTxOValue pp
               ]
      AlonzoEra ->
        object [ "extraPraosEntropy" .= protocolParamExtraPraosEntropy pp
               , "stakePoolTargetNum" .= protocolParamStakePoolTargetNum pp
               , "poolRetireMaxEpoch" .= protocolParamPoolRetireMaxEpoch pp
               , "decentralization" .= (fromRational $ protocolParamDecentralization pp :: Scientific)
               , "stakePoolDeposit" .= protocolParamStakePoolDeposit pp
               , "maxBlockHeaderSize" .= protocolParamMaxBlockHeaderSize pp
               , "maxBlockBodySize" .= protocolParamMaxBlockBodySize pp
               , "maxTxSize" .= protocolParamMaxTxSize pp
               , "treasuryCut" .= (fromRational $ protocolParamTreasuryCut pp :: Scientific)
               , "minPoolCost" .= protocolParamMinPoolCost pp
               , "monetaryExpansion" .= (fromRational $ protocolParamMonetaryExpansion pp :: Scientific)
               , "stakeAddressDeposit" .= protocolParamStakeAddressDeposit pp
               , "poolPledgeInfluence" .= (fromRational $ protocolParamPoolPledgeInfluence pp :: Scientific)
               , "protocolVersion" .= let (major, minor) = protocolParamProtocolVersion pp
                                      in object ["major" .= major, "minor" .= minor]
               , "txFeeFixed" .= protocolParamTxFeeFixed pp
               , "txFeePerByte" .= protocolParamTxFeePerByte pp
               , "minUTxOValue"  .= protocolParamMinUTxOValue pp
               -- Alonzo era additions
               , "costModels"  .= protocolParamCostModels pp
               , "execPrices" .= protocolParamPrices pp
               , "maxTxExecutionUnits" .= protocolParamMaxTxExUnits pp
               , "maxBlockExecutionUnits" .= protocolParamMaxBlockExUnits pp
               ]
-- ----------------------------------------------------------------------------
-- Updates to the protocol paramaters
--

-- | The representation of a change in the 'ProtocolParameters'.
--
data ProtocolParametersUpdate =
     ProtocolParametersUpdate {

       -- | Protocol version, major and minor. Updating the major version is
       -- used to trigger hard forks.
       --
       protocolUpdateProtocolVersion :: Maybe (Natural, Natural),

       -- | The decentralization parameter. This is fraction of slots that
       -- belong to the BFT overlay schedule, rather than the Praos schedule.
       -- So 1 means fully centralised, while 0 means fully decentralised.
       --
       -- This is the \"d\" parameter from the design document.
       --
       protocolUpdateDecentralization :: Maybe Rational,

       -- | Extra entropy for the Praos per-epoch nonce.
       --
       -- This can be used to add extra entropy during the decentralisation
       -- process. If the extra entropy can be demonstrated to be generated
       -- randomly then this method can be used to show that the initial
       -- federated operators did not subtly bias the initial schedule so that
       -- they retain undue influence after decentralisation.
       --
       protocolUpdateExtraPraosEntropy :: Maybe (Maybe PraosNonce),

       -- | The maximum permitted size of a block header.
       --
       -- This must be at least as big as the largest legitimate block headers
       -- but should not be too much larger, to help prevent DoS attacks.
       --
       -- Caution: setting this to be smaller than legitimate block headers is
       -- a sure way to brick the system!
       --
       protocolUpdateMaxBlockHeaderSize :: Maybe Natural,

       -- | The maximum permitted size of the block body (that is, the block
       -- payload, without the block header).
       --
       -- This should be picked with the Praos network delta security parameter
       -- in mind. Making this too large can severely weaken the Praos
       -- consensus properties.
       --
       -- Caution: setting this to be smaller than a transaction that can
       -- change the protocol parameters is a sure way to brick the system!
       --
       protocolUpdateMaxBlockBodySize :: Maybe Natural,

       -- | The maximum permitted size of a transaction.
       --
       -- Typically this should not be too high a fraction of the block size,
       -- otherwise wastage from block fragmentation becomes a problem, and
       -- the current implementation does not use any sophisticated box packing
       -- algorithm.
       --
       protocolUpdateMaxTxSize :: Maybe Natural,

       -- | The constant factor for the minimum fee calculation.
       --
       protocolUpdateTxFeeFixed :: Maybe Natural,

       -- | The linear factor for the minimum fee calculation.
       --
       protocolUpdateTxFeePerByte :: Maybe Natural,

       -- | The minimum permitted value for new UTxO entries, ie for
       -- transaction outputs.
       --
       protocolUpdateMinUTxOValue :: Maybe Lovelace,

       -- | The deposit required to register a stake address.
       --
       protocolUpdateStakeAddressDeposit :: Maybe Lovelace,

       -- | The deposit required to register a stake pool.
       --
       protocolUpdateStakePoolDeposit :: Maybe Lovelace,

       -- | The minimum value that stake pools are permitted to declare for
       -- their cost parameter.
       --
       protocolUpdateMinPoolCost :: Maybe Lovelace,

       -- | The maximum number of epochs into the future that stake pools
       -- are permitted to schedule a retirement.
       --
       protocolUpdatePoolRetireMaxEpoch :: Maybe EpochNo,

       -- | The equilibrium target number of stake pools.
       --
       -- This is the \"k\" incentives parameter from the design document.
       --
       protocolUpdateStakePoolTargetNum :: Maybe Natural,

       -- | The influence of the pledge in stake pool rewards.
       --
       -- This is the \"a_0\" incentives parameter from the design document.
       --
       protocolUpdatePoolPledgeInfluence :: Maybe Rational,

       -- | The monetary expansion rate. This determines the fraction of the
       -- reserves that are added to the fee pot each epoch.
       --
       -- This is the \"rho\" incentives parameter from the design document.
       --
       protocolUpdateMonetaryExpansion :: Maybe Rational,

       -- | The fraction of the fee pot each epoch that goes to the treasury.
       --
       -- This is the \"tau\" incentives parameter from the design document.
       --
       protocolUpdateTreasuryCut :: Maybe Rational
    }
  deriving (Eq, Show)

instance Semigroup ProtocolParametersUpdate where
    ppu1 <> ppu2 =
      ProtocolParametersUpdate {
        protocolUpdateProtocolVersion     = merge protocolUpdateProtocolVersion
      , protocolUpdateDecentralization    = merge protocolUpdateDecentralization
      , protocolUpdateExtraPraosEntropy   = merge protocolUpdateExtraPraosEntropy
      , protocolUpdateMaxBlockHeaderSize  = merge protocolUpdateMaxBlockHeaderSize
      , protocolUpdateMaxBlockBodySize    = merge protocolUpdateMaxBlockBodySize
      , protocolUpdateMaxTxSize           = merge protocolUpdateMaxTxSize
      , protocolUpdateTxFeeFixed          = merge protocolUpdateTxFeeFixed
      , protocolUpdateTxFeePerByte        = merge protocolUpdateTxFeePerByte
      , protocolUpdateMinUTxOValue        = merge protocolUpdateMinUTxOValue
      , protocolUpdateStakeAddressDeposit = merge protocolUpdateStakeAddressDeposit
      , protocolUpdateStakePoolDeposit    = merge protocolUpdateStakePoolDeposit
      , protocolUpdateMinPoolCost         = merge protocolUpdateMinPoolCost
      , protocolUpdatePoolRetireMaxEpoch  = merge protocolUpdatePoolRetireMaxEpoch
      , protocolUpdateStakePoolTargetNum  = merge protocolUpdateStakePoolTargetNum
      , protocolUpdatePoolPledgeInfluence = merge protocolUpdatePoolPledgeInfluence
      , protocolUpdateMonetaryExpansion   = merge protocolUpdateMonetaryExpansion
      , protocolUpdateTreasuryCut         = merge protocolUpdateTreasuryCut
      }
      where
        -- prefer the right hand side:
        merge :: (ProtocolParametersUpdate -> Maybe a) -> Maybe a
        merge f = f ppu2 `mplus` f ppu1

instance Monoid ProtocolParametersUpdate where
    mempty =
      ProtocolParametersUpdate {
        protocolUpdateProtocolVersion     = Nothing
      , protocolUpdateDecentralization    = Nothing
      , protocolUpdateExtraPraosEntropy   = Nothing
      , protocolUpdateMaxBlockHeaderSize  = Nothing
      , protocolUpdateMaxBlockBodySize    = Nothing
      , protocolUpdateMaxTxSize           = Nothing
      , protocolUpdateTxFeeFixed          = Nothing
      , protocolUpdateTxFeePerByte        = Nothing
      , protocolUpdateMinUTxOValue        = Nothing
      , protocolUpdateStakeAddressDeposit = Nothing
      , protocolUpdateStakePoolDeposit    = Nothing
      , protocolUpdateMinPoolCost         = Nothing
      , protocolUpdatePoolRetireMaxEpoch  = Nothing
      , protocolUpdateStakePoolTargetNum  = Nothing
      , protocolUpdatePoolPledgeInfluence = Nothing
      , protocolUpdateMonetaryExpansion   = Nothing
      , protocolUpdateTreasuryCut         = Nothing
      }


-- ----------------------------------------------------------------------------
-- Praos nonce
--

newtype PraosNonce = PraosNonce (Shelley.Hash StandardCrypto ByteString)
  deriving (Eq, Ord, Show, Generic)

instance ToJSON PraosNonce where
  toJSON (PraosNonce h) =
    Aeson.String $ Crypto.hashToTextAsHex h

instance FromJSON PraosNonce where
  parseJSON = withText "PraosNonce" $ \h ->
                case Crypto.hashFromTextAsHex h of
                  Nothing -> fail $ "Failed to decode PraosNonce: " <> Text.unpack h
                  Just nonce -> return $ PraosNonce nonce

makePraosNonce :: ByteString -> PraosNonce
makePraosNonce = PraosNonce . Crypto.hashWith id

toShelleyNonce :: Maybe PraosNonce -> Shelley.Nonce
toShelleyNonce Nothing               = Shelley.NeutralNonce
toShelleyNonce (Just (PraosNonce h)) = Shelley.Nonce (Crypto.castHash h)

fromPraosNonce :: Shelley.Nonce -> Maybe PraosNonce
fromPraosNonce Shelley.NeutralNonce = Nothing
fromPraosNonce (Shelley.Nonce h)    = Just (PraosNonce (Crypto.castHash h))


-- ----------------------------------------------------------------------------
-- Proposals embedded in transactions to update protocol parameters
--

data UpdateProposal =
     UpdateProposal
       !(Map (Hash GenesisKey) ProtocolParametersUpdate)
       !EpochNo
    deriving stock (Eq, Show)

instance HasTypeProxy UpdateProposal where
    data AsType UpdateProposal = AsUpdateProposal
    proxyToAsType _ = AsUpdateProposal

instance HasTextEnvelope UpdateProposal where
    textEnvelopeType _ = "UpdateProposalShelley"

--TODO: Jordan UpdateProposal needs to be parameterized by era or have access to the era
instance SerialiseAsCBOR UpdateProposal where
    serialiseToCBOR = CBOR.serializeEncoding' . toCBOR . toShelleyUpdate @StandardShelley
    deserialiseFromCBOR _ bs =
      fromShelleyUpdate @StandardShelley <$>
        CBOR.decodeAnnotator "UpdateProposal" fromCBOR (LBS.fromStrict bs)


makeShelleyUpdateProposal :: ProtocolParametersUpdate
                          -> [Hash GenesisKey]
                          -> EpochNo
                          -> UpdateProposal
makeShelleyUpdateProposal params genesisKeyHashes =
    --TODO decide how to handle parameter validation
    UpdateProposal (Map.fromList [ (kh, params) | kh <- genesisKeyHashes ])


-- ----------------------------------------------------------------------------
-- Genesis paramaters
--

data GenesisParameters era =
     GenesisParameters {

       -- | The reference time the system started. The time of slot zero.
       -- The time epoch against which all Ouroboros time slots are measured.
       --
       protocolParamSystemStart :: UTCTime,

       -- | The network identifier for this blockchain instance. This
       -- distinguishes the mainnet from testnets, and different testnets from
       -- each other.
       --
       protocolParamNetworkId :: NetworkId,

       -- | The Ouroboros Praos active slot coefficient, aka @f@.
       --
       protocolParamActiveSlotsCoefficient :: Rational,

       -- | The Ouroboros security paramaters, aka @k@. This is the maximum
       -- number of blocks the node would ever be prepared to roll back by.
       --
       -- Clients of the node following the chain should be prepared to handle
       -- the node switching forks up to this long.
       --
       protocolParamSecurity :: Int,

       -- | The number of Ouroboros time slots in an Ouroboros epoch.
       --
       protocolParamEpochLength :: EpochSize,

       -- | The time duration of a slot.
       --
       protocolParamSlotLength :: NominalDiffTime,

       -- | For Ouroboros Praos, the length of a KES period as a number of time
       -- slots. The KES keys get evolved once per KES period.
       --
       protocolParamSlotsPerKESPeriod :: Int,

       -- | The maximum number of times a KES key can be evolved before it is
       -- no longer considered valid. This can be less than the maximum number
       -- of times given the KES key size. For example the mainnet KES key size
       -- would allow 64 evolutions, but the max KES evolutions param is 62.
       --
       protocolParamMaxKESEvolutions ::  Int,

       -- | In the Shelley era, prior to decentralised governance, this is the
       -- number of genesis key delegates that need to agree for an update
       -- proposal to be enacted.
       --
       protocolParamUpdateQuorum ::  Int,

       -- | The maximum supply for Lovelace. This determines the initial value
       -- of the reserves.
       --
       protocolParamMaxLovelaceSupply :: Lovelace,

       -- | The initial values of the updateable 'ProtocolParameters'.
       --
       protocolInitialUpdateableProtocolParameters :: ProtocolParameters era
     }


-- ----------------------------------------------------------------------------
-- Conversion functions
--

toShelleyUpdate :: ( Ledger.Crypto ledgerera ~ StandardCrypto
                   , Shelley.PParamsDelta ledgerera
                     ~ Shelley.PParamsUpdate ledgerera
                   )
                => UpdateProposal -> Shelley.Update ledgerera
toShelleyUpdate (UpdateProposal ppup epochno) =
    Shelley.Update (toShelleyProposedPPUpdates ppup) epochno


toShelleyProposedPPUpdates :: forall ledgerera.
                              ( Ledger.Crypto ledgerera ~ StandardCrypto
                              , Shelley.PParamsDelta ledgerera
                                ~ Shelley.PParamsUpdate ledgerera
                              )
                            => Map (Hash GenesisKey) ProtocolParametersUpdate
                            -> Shelley.ProposedPPUpdates ledgerera
toShelleyProposedPPUpdates =
    Shelley.ProposedPPUpdates
  . Map.mapKeysMonotonic (\(GenesisKeyHash kh) -> kh)
  . Map.map (toShelleyPParamsUpdate @ledgerera)

toUpdate  :: ShelleyLedgerEra era ~ ledgerera
          => ShelleyBasedEra era
          -> UpdateProposal -> Shelley.Update ledgerera
toUpdate sbe (UpdateProposal ppup epochno) =
    Shelley.Update (toProposedPPUpdates sbe ppup) epochno

toProposedPPUpdates :: ShelleyLedgerEra era ~ ledgerera
                    => ShelleyBasedEra era
                    -> Map (Hash GenesisKey) ProtocolParametersUpdate
                    -> Shelley.ProposedPPUpdates ledgerera
toProposedPPUpdates sbe m =
  case sbe of
    ShelleyBasedEraShelley ->
      Shelley.ProposedPPUpdates
        . Map.mapKeysMonotonic (\(GenesisKeyHash kh) -> kh)
        $ Map.map toShelleyPParamsUpdate m
    ShelleyBasedEraAllegra ->
      Shelley.ProposedPPUpdates
        . Map.mapKeysMonotonic (\(GenesisKeyHash kh) -> kh)
        $ Map.map toShelleyPParamsUpdate m
    ShelleyBasedEraMary ->
      Shelley.ProposedPPUpdates
        . Map.mapKeysMonotonic (\(GenesisKeyHash kh) -> kh)
        $ Map.map toShelleyPParamsUpdate m
    ShelleyBasedEraAlonzo ->
      Shelley.ProposedPPUpdates
        . Map.mapKeysMonotonic (\(GenesisKeyHash kh) -> kh)
        $ Map.map toAlonzoPParamsUpdate m
{-
toPParamsUpdate :: ShelleyLedgerEra era ~ ledgerera
                => Shelley.UsesPParams ledgerera
                => ShelleyBasedEra era
                -> ProtocolParametersUpdate
                -> Core.PParamsDelta ledgerera
toPParamsUpdate sbe ppUp =
  case sbe of
    ShelleyBasedEraShelley -> toShelleyPParamsUpdate ppUp
    ShelleyBasedEraAllegra -> toShelleyPParamsUpdate ppUp
    ShelleyBasedEraMary -> toShelleyPParamsUpdate ppUp
    ShelleyBasedEraAlonzo -> toAlonzoPParamsUpdate ppUp
-}
toAlonzoPParamsUpdate :: ProtocolParametersUpdate
                      -> Alonzo.PParamsUpdate ledgerera
toAlonzoPParamsUpdate _ =
 Alonzo.PParams
      { Alonzo._minfeeA = maybeToStrictMaybe Nothing, --minfeeA',
        Alonzo._minfeeB = maybeToStrictMaybe Nothing, --minfeeB',
        Alonzo._maxBBSize = maybeToStrictMaybe Nothing, --maxBBSize',
        Alonzo._maxTxSize = maybeToStrictMaybe Nothing, --maxTxSize',
        Alonzo._maxBHSize = maybeToStrictMaybe Nothing, --maxBHSize',
        Alonzo._keyDeposit = maybeToStrictMaybe Nothing, --keyDeposit',
        Alonzo._poolDeposit = maybeToStrictMaybe Nothing, --poolDeposit',
        Alonzo._eMax = maybeToStrictMaybe Nothing, --eMax',
        Alonzo._nOpt = maybeToStrictMaybe Nothing, --nOpt',
        Alonzo._a0 = maybeToStrictMaybe Nothing, --a0',
        Alonzo._rho = maybeToStrictMaybe Nothing, --rho',
        Alonzo._tau = maybeToStrictMaybe Nothing, --tau',
        Alonzo._d = maybeToStrictMaybe Nothing, --d',
        Alonzo._extraEntropy = maybeToStrictMaybe Nothing, --extraEntropy',
        Alonzo._protocolVersion = maybeToStrictMaybe Nothing, --protocolVersion',
        Alonzo._minPoolCost = maybeToStrictMaybe Nothing, --minPoolCost',
        -- new/updated maybeToStrictMaybe Nothing, --for alonzo
        Alonzo._adaPerUTxOByte = maybeToStrictMaybe Nothing, --adaPerUTxOByte',
        Alonzo._costmdls = maybeToStrictMaybe Nothing, --costmdls',
        Alonzo._prices = maybeToStrictMaybe Nothing, --prices',
        Alonzo._maxTxExUnits = maybeToStrictMaybe Nothing, --maxTxExUnits',
        Alonzo._maxBlockExUnits = maybeToStrictMaybe Nothing -- = maxBlockExUnits'
      }

toShelleyPParamsUpdate :: ProtocolParametersUpdate
                       -> Shelley.PParamsUpdate ledgerera
toShelleyPParamsUpdate
    ProtocolParametersUpdate {
      protocolUpdateProtocolVersion
    , protocolUpdateDecentralization
    , protocolUpdateExtraPraosEntropy
    , protocolUpdateMaxBlockHeaderSize
    , protocolUpdateMaxBlockBodySize
    , protocolUpdateMaxTxSize
    , protocolUpdateTxFeeFixed
    , protocolUpdateTxFeePerByte
    , protocolUpdateMinUTxOValue
    , protocolUpdateStakeAddressDeposit
    , protocolUpdateStakePoolDeposit
    , protocolUpdateMinPoolCost
    , protocolUpdatePoolRetireMaxEpoch
    , protocolUpdateStakePoolTargetNum
    , protocolUpdatePoolPledgeInfluence
    , protocolUpdateMonetaryExpansion
    , protocolUpdateTreasuryCut
    } =
    Shelley.PParams {
      Shelley._minfeeA     = maybeToStrictMaybe protocolUpdateTxFeePerByte
    , Shelley._minfeeB     = maybeToStrictMaybe protocolUpdateTxFeeFixed
    , Shelley._maxBBSize   = maybeToStrictMaybe protocolUpdateMaxBlockBodySize
    , Shelley._maxTxSize   = maybeToStrictMaybe protocolUpdateMaxTxSize
    , Shelley._maxBHSize   = maybeToStrictMaybe protocolUpdateMaxBlockHeaderSize
    , Shelley._keyDeposit  = toShelleyLovelace <$>
                               maybeToStrictMaybe protocolUpdateStakeAddressDeposit
    , Shelley._poolDeposit = toShelleyLovelace <$>
                               maybeToStrictMaybe protocolUpdateStakePoolDeposit
    , Shelley._eMax        = maybeToStrictMaybe protocolUpdatePoolRetireMaxEpoch
    , Shelley._nOpt        = maybeToStrictMaybe protocolUpdateStakePoolTargetNum
    , Shelley._a0          = maybeToStrictMaybe protocolUpdatePoolPledgeInfluence
    , Shelley._rho         = Shelley.unitIntervalFromRational <$>
                               maybeToStrictMaybe protocolUpdateMonetaryExpansion
    , Shelley._tau         = Shelley.unitIntervalFromRational <$>
                               maybeToStrictMaybe protocolUpdateTreasuryCut
    , Shelley._d           = Shelley.unitIntervalFromRational <$>
                               maybeToStrictMaybe protocolUpdateDecentralization
    , Shelley._extraEntropy    = toShelleyNonce <$>
                                   maybeToStrictMaybe protocolUpdateExtraPraosEntropy
    , Shelley._protocolVersion = uncurry Shelley.ProtVer <$>
                                   maybeToStrictMaybe protocolUpdateProtocolVersion
    , Shelley._minUTxOValue    = toShelleyLovelace <$>
                                   maybeToStrictMaybe protocolUpdateMinUTxOValue
    , Shelley._minPoolCost     = toShelleyLovelace <$>
                                   maybeToStrictMaybe protocolUpdateMinPoolCost
    }

fromShelleyUpdate :: ( Ledger.Crypto ledgerera ~ StandardCrypto
                     , Shelley.PParamsDelta ledgerera
                       ~ Shelley.PParamsUpdate ledgerera
                     )
                  => Shelley.Update ledgerera -> UpdateProposal
fromShelleyUpdate (Shelley.Update ppup epochno) =
    UpdateProposal (fromShelleyProposedPPUpdates ppup) epochno


fromShelleyProposedPPUpdates :: ( Ledger.Crypto ledgerera ~ StandardCrypto
                                , Shelley.PParamsDelta ledgerera
                                  ~ Shelley.PParamsUpdate ledgerera
                                )
                             => Shelley.ProposedPPUpdates ledgerera
                             -> Map (Hash GenesisKey) ProtocolParametersUpdate
fromShelleyProposedPPUpdates =
    Map.map fromShelleyPParamsUpdate
  . Map.mapKeysMonotonic GenesisKeyHash
  . (\(Shelley.ProposedPPUpdates ppup) -> ppup)


fromShelleyPParamsUpdate :: Shelley.PParamsUpdate ledgerera
                         -> ProtocolParametersUpdate
fromShelleyPParamsUpdate
    Shelley.PParams {
      Shelley._minfeeA
    , Shelley._minfeeB
    , Shelley._maxBBSize
    , Shelley._maxTxSize
    , Shelley._maxBHSize
    , Shelley._keyDeposit
    , Shelley._poolDeposit
    , Shelley._eMax
    , Shelley._nOpt
    , Shelley._a0
    , Shelley._rho
    , Shelley._tau
    , Shelley._d
    , Shelley._extraEntropy
    , Shelley._protocolVersion
    , Shelley._minUTxOValue
    , Shelley._minPoolCost
    } =
    ProtocolParametersUpdate {
      protocolUpdateProtocolVersion     = (\(Shelley.ProtVer a b) -> (a,b)) <$>
                                          strictMaybeToMaybe _protocolVersion
    , protocolUpdateDecentralization    = Shelley.unitIntervalToRational <$>
                                            strictMaybeToMaybe _d
    , protocolUpdateExtraPraosEntropy   = fromPraosNonce <$>
                                            strictMaybeToMaybe _extraEntropy
    , protocolUpdateMaxBlockHeaderSize  = strictMaybeToMaybe _maxBHSize
    , protocolUpdateMaxBlockBodySize    = strictMaybeToMaybe _maxBBSize
    , protocolUpdateMaxTxSize           = strictMaybeToMaybe _maxTxSize
    , protocolUpdateTxFeeFixed          = strictMaybeToMaybe _minfeeB
    , protocolUpdateTxFeePerByte        = strictMaybeToMaybe _minfeeA
    , protocolUpdateMinUTxOValue        = fromShelleyLovelace <$>
                                            strictMaybeToMaybe _minUTxOValue
    , protocolUpdateStakeAddressDeposit = fromShelleyLovelace <$>
                                            strictMaybeToMaybe _keyDeposit
    , protocolUpdateStakePoolDeposit    = fromShelleyLovelace <$>
                                            strictMaybeToMaybe _poolDeposit
    , protocolUpdateMinPoolCost         = fromShelleyLovelace <$>
                                            strictMaybeToMaybe _minPoolCost
    , protocolUpdatePoolRetireMaxEpoch  = strictMaybeToMaybe _eMax
    , protocolUpdateStakePoolTargetNum  = strictMaybeToMaybe _nOpt
    , protocolUpdatePoolPledgeInfluence = strictMaybeToMaybe _a0
    , protocolUpdateMonetaryExpansion   = Shelley.unitIntervalToRational <$>
                                            strictMaybeToMaybe _rho
    , protocolUpdateTreasuryCut         = Shelley.unitIntervalToRational <$>
                                            strictMaybeToMaybe _tau
    }


fromShelleyPParams
  :: ShelleyBasedEra era
  -> Shelley.PParams (ShelleyLedgerEra era)
  -> ProtocolParameters era
fromShelleyPParams shelleyBasedEra' pparams =
  case shelleyBasedEra' of
    ShelleyBasedEraShelley ->
      ProtocolParameters
        { protocolParamProtocolVersion     = (\(Shelley.ProtVer a b) -> (a,b))
                                               $ Shelley._protocolVersion pparams
        , protocolParamDecentralization    = Shelley.unitIntervalToRational $ Shelley._d pparams
        , protocolParamExtraPraosEntropy   = fromPraosNonce $ Shelley._extraEntropy pparams
        , protocolParamMaxBlockHeaderSize  = Shelley._maxBHSize pparams
        , protocolParamMaxBlockBodySize    = Shelley._maxBBSize pparams
        , protocolParamMaxTxSize           = Shelley._maxTxSize pparams
        , protocolParamTxFeeFixed          = Shelley._minfeeB pparams
        , protocolParamTxFeePerByte        = Shelley._minfeeA pparams
        , protocolParamMinUTxOValue        = Just . fromShelleyLovelace $ Shelley._minUTxOValue pparams
        , protocolParamStakeAddressDeposit = fromShelleyLovelace $ Shelley._keyDeposit pparams
        , protocolParamStakePoolDeposit    = fromShelleyLovelace $ Shelley._poolDeposit pparams
        , protocolParamMinPoolCost         = fromShelleyLovelace $ Shelley._minPoolCost pparams
        , protocolParamPoolRetireMaxEpoch  = Shelley._eMax pparams
        , protocolParamStakePoolTargetNum  = Shelley._nOpt pparams
        , protocolParamPoolPledgeInfluence = Shelley._a0 pparams
        , protocolParamMonetaryExpansion   = Shelley.unitIntervalToRational $ Shelley._rho pparams
        , protocolParamTreasuryCut         = Shelley.unitIntervalToRational $ Shelley._tau pparams
        , protocolParamUTxOCostPerByte     = Nothing
        , protocolParamCostModels          = Nothing
        , protocolParamPrices              = Nothing
        , protocolParamMaxTxExUnits        = Nothing
        , protocolParamMaxBlockExUnits     = Nothing
        }

    ShelleyBasedEraAllegra ->
      ProtocolParameters
        { protocolParamProtocolVersion     = (\(Shelley.ProtVer a b) -> (a,b))
                                               $ Shelley._protocolVersion pparams
        , protocolParamDecentralization    = Shelley.unitIntervalToRational $ Shelley._d pparams
        , protocolParamExtraPraosEntropy   = fromPraosNonce $ Shelley._extraEntropy pparams
        , protocolParamMaxBlockHeaderSize  = Shelley._maxBHSize pparams
        , protocolParamMaxBlockBodySize    = Shelley._maxBBSize pparams
        , protocolParamMaxTxSize           = Shelley._maxTxSize pparams
        , protocolParamTxFeeFixed          = Shelley._minfeeB pparams
        , protocolParamTxFeePerByte        = Shelley._minfeeA pparams
        , protocolParamMinUTxOValue        = Just . fromShelleyLovelace $ Shelley._minUTxOValue pparams
        , protocolParamStakeAddressDeposit = fromShelleyLovelace $ Shelley._keyDeposit pparams
        , protocolParamStakePoolDeposit    = fromShelleyLovelace $ Shelley._poolDeposit pparams
        , protocolParamMinPoolCost         = fromShelleyLovelace $ Shelley._minPoolCost pparams
        , protocolParamPoolRetireMaxEpoch  = Shelley._eMax pparams
        , protocolParamStakePoolTargetNum  = Shelley._nOpt pparams
        , protocolParamPoolPledgeInfluence = Shelley._a0 pparams
        , protocolParamMonetaryExpansion   = Shelley.unitIntervalToRational $ Shelley._rho pparams
        , protocolParamTreasuryCut         = Shelley.unitIntervalToRational $ Shelley._tau pparams
        , protocolParamUTxOCostPerByte     = Nothing
        , protocolParamCostModels          = Nothing
        , protocolParamPrices              = Nothing
        , protocolParamMaxTxExUnits        = Nothing
        , protocolParamMaxBlockExUnits     = Nothing
        }
    ShelleyBasedEraMary ->
      ProtocolParameters
        { protocolParamProtocolVersion     = (\(Shelley.ProtVer a b) -> (a,b))
                                               $ Shelley._protocolVersion pparams
        , protocolParamDecentralization    = Shelley.unitIntervalToRational $ Shelley._d pparams
        , protocolParamExtraPraosEntropy   = fromPraosNonce $ Shelley._extraEntropy pparams
        , protocolParamMaxBlockHeaderSize  = Shelley._maxBHSize pparams
        , protocolParamMaxBlockBodySize    = Shelley._maxBBSize pparams
        , protocolParamMaxTxSize           = Shelley._maxTxSize pparams
        , protocolParamTxFeeFixed          = Shelley._minfeeB pparams
        , protocolParamTxFeePerByte        = Shelley._minfeeA pparams
        , protocolParamMinUTxOValue        = Just . fromShelleyLovelace $ Shelley._minUTxOValue pparams
        , protocolParamStakeAddressDeposit = fromShelleyLovelace $ Shelley._keyDeposit pparams
        , protocolParamStakePoolDeposit    = fromShelleyLovelace $ Shelley._poolDeposit pparams
        , protocolParamMinPoolCost         = fromShelleyLovelace $ Shelley._minPoolCost pparams
        , protocolParamPoolRetireMaxEpoch  = Shelley._eMax pparams
        , protocolParamStakePoolTargetNum  = Shelley._nOpt pparams
        , protocolParamPoolPledgeInfluence = Shelley._a0 pparams
        , protocolParamMonetaryExpansion   = Shelley.unitIntervalToRational $ Shelley._rho pparams
        , protocolParamTreasuryCut         = Shelley.unitIntervalToRational $ Shelley._tau pparams
        , protocolParamUTxOCostPerByte     = Nothing
        , protocolParamCostModels          = Nothing
        , protocolParamPrices              = Nothing
        , protocolParamMaxTxExUnits        = Nothing
        , protocolParamMaxBlockExUnits     = Nothing
        }
    ShelleyBasedEraAlonzo ->
            ProtocolParameters
        { protocolParamProtocolVersion     = (\(Shelley.ProtVer a b) -> (a,b))
                                               $ Shelley._protocolVersion pparams
        , protocolParamDecentralization    = Shelley.unitIntervalToRational $ Shelley._d pparams
        , protocolParamExtraPraosEntropy   = fromPraosNonce $ Shelley._extraEntropy pparams
        , protocolParamMaxBlockHeaderSize  = Shelley._maxBHSize pparams
        , protocolParamMaxBlockBodySize    = Shelley._maxBBSize pparams
        , protocolParamMaxTxSize           = Shelley._maxTxSize pparams
        , protocolParamTxFeeFixed          = Shelley._minfeeB pparams
        , protocolParamTxFeePerByte        = Shelley._minfeeA pparams
        , protocolParamMinUTxOValue        = Nothing
        , protocolParamStakeAddressDeposit = fromShelleyLovelace $ Shelley._keyDeposit pparams
        , protocolParamStakePoolDeposit    = fromShelleyLovelace $ Shelley._poolDeposit pparams
        , protocolParamMinPoolCost         = fromShelleyLovelace $ Shelley._minPoolCost pparams
        , protocolParamPoolRetireMaxEpoch  = Shelley._eMax pparams
        , protocolParamStakePoolTargetNum  = Shelley._nOpt pparams
        , protocolParamPoolPledgeInfluence = Shelley._a0 pparams
        , protocolParamMonetaryExpansion   = Shelley.unitIntervalToRational $ Shelley._rho pparams
        , protocolParamTreasuryCut         = Shelley.unitIntervalToRational $ Shelley._tau pparams
        , protocolParamUTxOCostPerByte     = Just 0
        , protocolParamCostModels          = Just $ CostModel empty
        , protocolParamPrices              = Just $ Prices 0 0
        , protocolParamMaxTxExUnits        = Just . MaxTxExecutionUnits $ ExecutionUnits 0 0
        , protocolParamMaxBlockExUnits     = Just . MaxBlockExecutionUnits $ ExecutionUnits 0 0
        }



fromShelleyGenesis
  :: ShelleyBasedEra era
  -> Shelley.ShelleyGenesis (ShelleyLedgerEra era)
  -> GenesisParameters era
fromShelleyGenesis
    sbe
    Shelley.ShelleyGenesis {
      Shelley.sgSystemStart
    , Shelley.sgNetworkMagic
    , Shelley.sgNetworkId
    , Shelley.sgActiveSlotsCoeff
    , Shelley.sgSecurityParam
    , Shelley.sgEpochLength
    , Shelley.sgSlotsPerKESPeriod
    , Shelley.sgMaxKESEvolutions
    , Shelley.sgSlotLength
    , Shelley.sgUpdateQuorum
    , Shelley.sgMaxLovelaceSupply
    , Shelley.sgProtocolParams
    , Shelley.sgGenDelegs    = _  -- unused, might be of interest
    , Shelley.sgInitialFunds = _  -- unused, not retained by the node
    , Shelley.sgStaking      = _  -- unused, not retained by the node
    } =
    GenesisParameters {
      protocolParamSystemStart            = sgSystemStart
    , protocolParamNetworkId              = fromShelleyNetwork sgNetworkId
                                              (NetworkMagic sgNetworkMagic)
    , protocolParamActiveSlotsCoefficient = sgActiveSlotsCoeff
    , protocolParamSecurity               = fromIntegral sgSecurityParam
    , protocolParamEpochLength            = sgEpochLength
    , protocolParamSlotLength             = sgSlotLength
    , protocolParamSlotsPerKESPeriod      = fromIntegral sgSlotsPerKESPeriod
    , protocolParamMaxKESEvolutions       = fromIntegral sgMaxKESEvolutions
    , protocolParamUpdateQuorum           = fromIntegral sgUpdateQuorum
    , protocolParamMaxLovelaceSupply      = Lovelace
                                              (fromIntegral sgMaxLovelaceSupply)
    , protocolInitialUpdateableProtocolParameters = fromShelleyPParams sbe
                                                      sgProtocolParams
    }


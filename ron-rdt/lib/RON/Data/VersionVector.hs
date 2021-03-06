{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- | Version Vector
module RON.Data.VersionVector (
    VersionVector,
) where

import           RON.Prelude

import           Data.Hashable (hashWithSalt)
import qualified Data.Map.Strict as Map

import           RON.Data.Internal (Reducible, Rep, Replicated (encoding),
                                    ReplicatedAsObject, getObjectState,
                                    newObject, objectEncoding, readObject,
                                    reducibleOpType, stateFromChunk,
                                    stateToChunk)
import           RON.Event (getEventUuid)
import           RON.Semilattice (Semilattice)
import           RON.Types (ObjectRef (ObjectRef), Op (Op, opId), UUID (UUID), WireStateChunk (WireStateChunk, stateBody, stateType))
import qualified RON.UUID as UUID

type Origin = Word64

opTime :: Op -> Word64
opTime Op{opId = UUID time _} = time

opOrigin :: Op -> Word64
opOrigin Op{opId = UUID _ origin} = origin

latter :: Op -> Op -> Op
latter = maxOn opTime

-- | Version Vector type. May be used both in typed and untyped contexts.
newtype VersionVector = VersionVector (Map Origin Op)
    deriving (Eq, Show)

instance Hashable VersionVector where
    hashWithSalt s (VersionVector vv) = hashWithSalt s $ Map.assocs vv

instance Semigroup VersionVector where
    (<>) = coerce $ Map.unionWith latter

instance Monoid VersionVector where
    mempty = VersionVector mempty

-- | Laws:
-- 1. Idempotent because 'Map.unionWith' is idempotent.
-- 2. Commutative because 'latter' is commutative.
instance Semilattice VersionVector

instance Reducible VersionVector where
    reducibleOpType = vvType

    stateFromChunk ops =
        VersionVector $ Map.fromListWith latter [(opOrigin op, op) | op <- ops]

    stateToChunk (VersionVector vv) = Map.elems vv

wireStateChunk :: [Op] -> WireStateChunk
wireStateChunk stateBody = WireStateChunk{stateType = vvType, stateBody}

-- | Name-UUID to use as Version Vector type marker.
vvType :: UUID
vvType = $(UUID.liftName "vv")

instance Replicated VersionVector where
    encoding = objectEncoding

instance ReplicatedAsObject VersionVector where
    type Rep VersionVector = VersionVector

    newObject (VersionVector vv) = do
        oid <- getEventUuid
        let ops = Map.elems vv
        modify' $ Map.insert oid $ wireStateChunk ops
        pure $ ObjectRef oid

    readObject = getObjectState

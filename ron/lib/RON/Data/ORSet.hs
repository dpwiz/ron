{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module RON.Data.ORSet
    ( ORSet (..)
    , ObjectORSet (..)
    , ORSetRaw
    , addNewRef
    , addRef
    , addValue
    , removeRef
    , removeValue
    ) where

import           RON.Internal.Prelude

import           Control.Monad.Except (MonadError)
import           Control.Monad.State.Strict (StateT, get, modify, put)
import           Control.Monad.Writer.Strict (lift, tell)
import qualified Data.Map.Strict as Map

import           RON.Data.Internal
import           RON.Event (Clock, getEventUuid)
import           RON.Types (Atom, Object (..), Op' (..), StateChunk (..), UUID)
import           RON.UUID (pattern Zero)
import qualified RON.UUID as UUID

data SetItem = SetItem{itemIsAlive :: Bool, itemOriginalOp :: Op'}
    deriving (Eq, Show)

instance Semigroup SetItem where
    (<>) = minOn itemIsAlive

itemFromOp :: Op' -> (UUID, SetItem)
itemFromOp itemOriginalOp@Op'{..} = (itemId, item) where
    itemIsAlive = opRef == Zero
    itemId = if itemIsAlive then opEvent else opRef
    item = SetItem{..}

newtype ORSetRaw = ORSetRaw (Map UUID SetItem)
    deriving (Eq, Show)

instance Semigroup ORSetRaw where
    ORSetRaw set1 <> ORSetRaw set2 = ORSetRaw $ Map.unionWith (<>) set1 set2

instance Monoid ORSetRaw where
    mempty = ORSetRaw mempty

instance Reducible ORSetRaw where
    type OpType ORSetRaw = "set"

    stateFromChunk = ORSetRaw . Map.fromListWith (<>) . map itemFromOp

    stateToChunk (ORSetRaw set) =
        mkStateChunk . sortOn opEvent . map itemOriginalOp $ Map.elems set

setType :: UUID
setType = fromJust $ UUID.mkName "set"

newtype ORSet a = ORSet [a]

newtype ObjectORSet a = ObjectORSet [a]

instance ReplicatedAsPayload a => Replicated (ORSet a) where
    encoding = objectEncoding

instance ReplicatedAsPayload a => ReplicatedAsObject (ORSet a) where
    objectOpType = setType

    newObject (ORSet items) = collectFrame $ do
        ops <- for items $ \item -> do
            e <- lift getEventUuid
            pure $ Op' e Zero $ toPayload item
        oid <- lift getEventUuid
        let version = maximumDef oid $ map opEvent ops
        tell $ Map.singleton (setType, oid) $ StateChunk version ops
        pure oid

    getObject obj@Object{..} = do
        StateChunk{..} <- getObjectStateChunk obj
        mItems <- for stateBody $ \Op'{..} -> case opRef of
            Zero -> Just <$> fromPayload opPayload
            _    -> pure Nothing
        pure . ORSet $ catMaybes mItems

instance ReplicatedAsObject a => Replicated (ObjectORSet a) where
    encoding = objectEncoding

instance ReplicatedAsObject a => ReplicatedAsObject (ObjectORSet a) where
    objectOpType = setType

    newObject (ObjectORSet items) = collectFrame $ do
        ops <- for items $ \item -> do
            e <- lift getEventUuid
            Object{objectId = itemId} <- lift $ newObject item
            pure . Op' e Zero $ toPayload itemId
        oid <- lift getEventUuid
        let version = maximumDef oid $ map opEvent ops
        tell . Map.singleton (setType, oid) $ StateChunk version ops
        pure oid

    getObject obj@Object{..} = do
        StateChunk{..} <- getObjectStateChunk obj
        mItems <- for stateBody $ \Op'{..} -> case opRef of
            Zero -> do
                oid <- fromPayload opPayload
                Just <$> getObject (Object oid objectFrame)
            _    -> pure Nothing
        pure . ObjectORSet $ catMaybes mItems

-- | XXX Internal. Common implementation of 'addValue' and 'addRef'.
add ::  ( ReplicatedAsObject a
        , ReplicatedAsPayload b
        , Clock m, MonadError String m
        )
    => b -> StateT (Object a) m ()
add item = do
    obj@Object{..} <- get
    StateChunk{..} <- either throwError pure $ getObjectStateChunk obj
    e <- getEventUuid
    let p = toPayload item
    let newOp = Op' e Zero p
    let chunk' = stateBody ++ [newOp]
    let state' = StateChunk e chunk'
    put Object
        {objectFrame = Map.insert (setType, objectId) state' objectFrame, ..}

addValue
    :: (ReplicatedAsPayload a, Clock m, MonadError String m)
    => a -> StateT (Object (ORSet a)) m ()
addValue = add

addRef
    :: (ReplicatedAsObject a, Clock m, MonadError String m)
    => Object a -> StateT (Object (ObjectORSet a)) m ()
addRef = add . objectId

addNewRef
    :: forall a m
    . (ReplicatedAsObject a, Clock m, MonadError String m)
    => a -> StateT (Object (ObjectORSet a)) m ()
addNewRef item = do
    itemObj@(Object _ itemFrame) <- lift $ newObject item
    modify $ \Object{..} -> Object{objectFrame = objectFrame <> itemFrame, ..}
    addRef itemObj

removeBy :: ([Atom] -> Bool) -> StateT (Object (ORSet a)) m ()
removeBy = undefined

removeValue :: ReplicatedAsPayload a => a -> StateT (Object (ORSet a)) m ()
removeValue = removeBy . eqPayload

removeRef :: Object a -> StateT (Object (ORSet a)) m ()
removeRef = removeBy . eqRef

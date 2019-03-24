{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TemplateHaskell #-}

module Swarm.RON.Status (
    Status (..),
    decode,
    decoding,
    -- * Statuses
    ok,
) where

import           Control.Exception (mask_)
import           Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as Map
import           Data.Proxy (Proxy)
import           Foreign (FinalizerPtr, ForeignPtr, Ptr, allocaArray,
                          newForeignPtr, peekElemOff, wordPtrToPtr)
import           Language.C.Inline.Context (ctxTypesTable)
import qualified Language.C.Inline.Cpp as Cpp
import           Language.C.Types (TypeSpecifier (TypeName))

import           RON.UUID (UUID (UUID))

-- | Class @ron::Status@
data Status = Status{code :: UUID, comment :: ByteString}
    deriving Show

Cpp.context
    $   Cpp.cppCtx
    <>  Cpp.fptrCtx
    <>  mempty
        { ctxTypesTable = Map.singleton (TypeName "Status") [t| Proxy Status |]
        }
Cpp.include "<swarm/ron/status.hpp>"
Cpp.verbatim "typedef ron::Status Status;"

ok :: UUID
ok = UUID
    [Cpp.pure| uint64_t { uint64_t(ron::Status::OK.code().value ()) } |]
    [Cpp.pure| uint64_t { uint64_t(ron::Status::OK.code().origin()) } |]

--     | ENDOFFRAME
--     | NOT_IMPLEMENTED
--     | NOT_FOUND
--     | BAD_STATE
--     | BADARGS
--     | BADSYNTAX
--     | DB_FAIL
--     | IOFAIL
--     | BADFRAME
--     | BADID
--     | BADREF
--     | BADVALUE

--     | NOTYPE
--     | NOTOPEN

--     | CHAINBREAK
--     | HASHBREAK
--     | TREEBREAK
--     | CAUSEBREAK

--     | TREEGAP
--     | YARNGAP

--     | REPEAT
--     | REORDER

decode :: ForeignPtr (Proxy Status) -> IO Status
decode statusFP =
    allocaArray 4 $ \arena -> do
        [Cpp.block| void {
            uint64_t * const arena = $(uint64_t * arena);
            uint64_t & x   = arena[0];
            uint64_t & y   = arena[1];
            uint64_t & ptr = arena[2];
            uint64_t & len = arena[3];
            Status & status = * $fptr-ptr:(Status * statusFP);
            x = uint64_t(status.code().value());
            y = uint64_t(status.code().origin());
            ptr = uintptr_t(status.comment().data());
            len = status.comment().length();
        } |]
        code <- UUID <$> peekElemOff arena 0 <*> peekElemOff arena 1
        ptr <- wordPtrToPtr . fromIntegral <$> peekElemOff arena 2
        len <- fromIntegral <$> peekElemOff arena 3
        comment <- BS.packCStringLen (ptr, len)
        pure Status{code, comment}

decoding :: IO (Ptr (Proxy Status)) -> IO Status
decoding action = do
    fptr <- mask_ $ do
        ptr <- action
        newForeignPtr free ptr
    decode fptr

foreign import ccall "&free" free :: FinalizerPtr a

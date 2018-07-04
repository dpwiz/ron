module Internal.Prelude
    ( module Internal.Prelude
    , module X
    ) where

import           Control.Applicative as X
import           Control.Monad as X
import           Data.Bits ((.&.))
import           Data.ByteString as X (ByteString)
import qualified Data.ByteString.Lazy as BSL
import           Data.Int as X (Int16, Int32, Int64, Int8)
import           Data.Maybe as X
import           Data.Semigroup as X ((<>))
import           Data.Word as X (Word16, Word32, Word64, Word8)

type ByteStringL = BSL.ByteString

type Word2 = Word8

type Word4 = Word8

type Word6 = Word8

type Word60 = Word64

leastSignificant60 :: Word64 -> Word60
leastSignificant60 = (0x0FFFFFFFFFFFFFFF .&.)

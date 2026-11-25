/**
 * https://github.com/Uniswap/v4-core/blob/main/src/libraries/TickBitmap.sol
 * SPDX-License-Identifier: MIT
 */
pragma solidity ^0.8.34;

import { BitMath } from "@uniswap/v4-core/src/libraries/BitMath.sol";
import { IMetadexCLPool } from "../../../interfaces/IMetadexCLPool.sol";
import { TickBitmap } from "@uniswap/v4-core/src/libraries/TickBitmap.sol";

/**
 * @title Metadex Tick Bitmap.
 * @notice Finds the next initialized tick in the Metadex CL pool's tick bitmap.
 */
// forge-lint: disable-next-item(calls-loop, unsafe-typecast)
library MetadexTickBitmap {
    /**
     * @notice Returns the next initialized tick in the bitmap word of a tick, or the word's end.
     * @param pool The Metadex CL pool.
     * @param tick The starting tick.
     * @param tickSpacing The pool's tick spacing.
     * @param lte True to search at or below the tick, false to search above it.
     * @return next The next initialized tick, or the word's end.
     * @return initialized True when next is initialized.
     * @dev Vendored from TickBitmap.nextInitializedTickWithinOneWord, reading the bitmap word from the pool.
     */
    function nextInitializedTickWithinOneWord(address pool, int24 tick, int24 tickSpacing, bool lte)
        internal
        view
        returns (int24 next, bool initialized)
    {
        // Unchecked: vendored, unchecked in Uniswap v4 under solc ^0.8.0.
        unchecked {
            int24 compressed = TickBitmap.compress(tick, tickSpacing);

            if (lte) {
                (int16 wordPos, uint8 bitPos) = TickBitmap.position(compressed);
                // All the 1s at or to the right of the current bitPos.
                uint256 mask = type(uint256).max >> (uint256(type(uint8).max) - bitPos);
                uint256 masked = IMetadexCLPool(pool).tickBitmap(wordPos) & mask;

                // Without initialized ticks at or to the right of the current tick, the rightmost in the word.
                initialized = masked != 0;
                next = initialized
                    ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
                    : (compressed - int24(uint24(bitPos))) * tickSpacing;
            } else {
                // Start from the word of the next tick, since the current tick state does not matter.
                (int16 wordPos, uint8 bitPos) = TickBitmap.position(++compressed);
                // All the 1s at or to the left of the bitPos.
                uint256 mask = ~((1 << bitPos) - 1);
                uint256 masked = IMetadexCLPool(pool).tickBitmap(wordPos) & mask;

                // Without initialized ticks to the left of the current tick, the leftmost in the word.
                initialized = masked != 0;
                next = initialized
                    ? (compressed + int24(uint24(BitMath.leastSignificantBit(masked) - bitPos))) * tickSpacing
                    : (compressed + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
            }
        }
    }
}

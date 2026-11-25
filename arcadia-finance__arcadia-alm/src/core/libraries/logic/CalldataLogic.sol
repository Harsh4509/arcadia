/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { CoreImmutables } from "../../types/CoreImmutables.sol";
import { IMetadexCLPositionManager } from "../../../interfaces/IMetadexCLPositionManager.sol";

/**
 * @title Calldata Logic.
 * @author Pragma Labs
 * @notice Decodes the tight-packed keeper payloads and the metadata appended to the calldata.
 */
// forge-lint: disable-next-item(require-revert-in-loop)
library CalldataLogic {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The length of a payload naming a range by index and token id.
    uint256 internal constant CLOSE_RANGE_LENGTH = 13;

    // The length of a payload naming a position by token id.
    uint256 internal constant COLLECT_LENGTH = 12;

    // The length of one controller of a controller list payload.
    uint256 internal constant CONTROLLER_LENGTH = 20;

    // The length of a payload removing liquidity from a range.
    uint256 internal constant DECREASE_LIQUIDITY_LENGTH = 93;

    // The length of a payload adding liquidity to a range's unstaked side.
    uint256 internal constant INCREASE_LIQUIDITY_LENGTH = 141;

    // The offset of acceptPenalty in a payload adding liquidity to a range's staked side.
    uint256 internal constant INCREASE_STAKED_LIQUIDITY_ACCEPT_PENALTY_OFFSET = 141;

    // The length of a payload adding liquidity to a range's staked side.
    uint256 internal constant INCREASE_STAKED_LIQUIDITY_LENGTH = 142;

    // The length of a payload opening a range.
    uint256 internal constant OPEN_RANGE_LENGTH = 134;

    // The length of a whole-queue clear payload, and of the head of a controller list payload.
    uint256 internal constant QUEUE_LENGTH = 2;

    // The length of a payload minting a range's staked side.
    uint256 internal constant STAKE_LENGTH = 141;

    // The length of a payload swapping against the pool.
    uint256 internal constant SWAP_VIA_POOL_LENGTH = 85;

    // The length of a payload swapping via a router trampoline, before its calldata.
    uint256 internal constant SWAP_VIA_ROUTER_LENGTH = 85;

    // The offset of acceptPenalty in a payload removing liquidity from a range's staked side.
    uint256 internal constant UNSTAKE_ACCEPT_PENALTY_OFFSET = 93;

    // The length of a payload removing liquidity from a range's staked side.
    uint256 internal constant UNSTAKE_LENGTH = 94;

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidPayload();

    /* //////////////////////////////////////////////////////////////
                                 DECODERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Decodes a range.
     * @param payload The tight-packed payload.
     * @return index The index of the range.
     * @return tokenId The token id the range is expected to hold on the side the command acts on.
     */
    function decodeRange(bytes calldata payload) internal pure returns (uint256 index, uint256 tokenId) {
        assertLength(payload, CLOSE_RANGE_LENGTH);
        (index, tokenId) = readKey(payload);
    }

    /**
     * @notice Decodes a position.
     * @param payload The tight-packed payload.
     * @return params The collect parameters, holding the token id of the position.
     */
    function decodePosition(bytes calldata payload)
        internal
        pure
        returns (IMetadexCLPositionManager.CollectParams memory params)
    {
        assertLength(payload, COLLECT_LENGTH);

        assembly ("memory-safe") {
            mstore(params, shr(160, calldataload(payload.offset)))
        }
    }

    /**
     * @notice Decodes a liquidity removal from one side of a range.
     * @param payload The tight-packed payload.
     * @param staked True for the staked side, whose payload carries acceptPenalty.
     * @return index The index of the range.
     * @return params The decrease parameters, holding the token id of the side the range is expected to hold.
     * @return acceptPenalty True to remove inside the penalty window anyway, forfeiting the pending emissions.
     */
    function decodeDecrease(bytes calldata payload, bool staked)
        internal
        pure
        returns (uint256 index, IMetadexCLPositionManager.DecreaseLiquidityParams memory params, bool acceptPenalty)
    {
        assertLength(payload, staked ? UNSTAKE_LENGTH : DECREASE_LIQUIDITY_LENGTH);

        uint256 tokenId;
        (index, tokenId) = readKey(payload);
        assembly ("memory-safe") {
            mstore(params, tokenId)
            mstore(add(params, 0x20), shr(128, calldataload(add(payload.offset, 13))))
            mstore(add(params, 0x40), calldataload(add(payload.offset, 29)))
            mstore(add(params, 0x60), calldataload(add(payload.offset, 61)))
        }
        if (staked) acceptPenalty = readBool(payload, UNSTAKE_ACCEPT_PENALTY_OFFSET);
    }

    /**
     * @notice Decodes the opening of a range.
     * @param payload The tight-packed payload.
     * @return params The mint parameters, holding the ticks, amounts and minimums.
     */
    function decodeOpen(bytes calldata payload)
        internal
        pure
        returns (IMetadexCLPositionManager.MintParams memory params)
    {
        assertLength(payload, OPEN_RANGE_LENGTH);

        assembly ("memory-safe") {
            mstore(add(params, 0x60), signextend(2, shr(232, calldataload(payload.offset))))
            mstore(add(params, 0x80), signextend(2, shr(232, calldataload(add(payload.offset, 3)))))
            mstore(add(params, 0xa0), calldataload(add(payload.offset, 6)))
            mstore(add(params, 0xc0), calldataload(add(payload.offset, 38)))
            mstore(add(params, 0xe0), calldataload(add(payload.offset, 70)))
            mstore(add(params, 0x100), calldataload(add(payload.offset, 102)))
        }
    }

    /**
     * @notice Decodes an addition of liquidity to one side of a range.
     * @param payload The tight-packed payload.
     * @param staked True for the staked side, whose payload carries acceptPenalty.
     * @return index The index of the range.
     * @return params The increase parameters, holding the token id of the side the range is expected to hold.
     * @return acceptPenalty True to top up inside the penalty window anyway, forfeiting the pending emissions.
     */
    function decodeIncrease(bytes calldata payload, bool staked)
        internal
        pure
        returns (uint256 index, IMetadexCLPositionManager.IncreaseLiquidityParams memory params, bool acceptPenalty)
    {
        assertLength(payload, staked ? INCREASE_STAKED_LIQUIDITY_LENGTH : INCREASE_LIQUIDITY_LENGTH);

        uint256 tokenId;
        (index, tokenId) = readKey(payload);
        assembly ("memory-safe") {
            mstore(params, tokenId)
            mstore(add(params, 0x20), calldataload(add(payload.offset, 13)))
            mstore(add(params, 0x40), calldataload(add(payload.offset, 45)))
            mstore(add(params, 0x60), calldataload(add(payload.offset, 77)))
            mstore(add(params, 0x80), calldataload(add(payload.offset, 109)))
        }
        if (staked) acceptPenalty = readBool(payload, INCREASE_STAKED_LIQUIDITY_ACCEPT_PENALTY_OFFSET);
    }

    /**
     * @notice Decodes the minting of a range's staked side.
     * @param payload The tight-packed payload.
     * @return index The index of the range.
     * @return tokenId The unstaked token id the range is expected to hold.
     * @return params The mint parameters, holding the amounts and minimums.
     */
    function decodeStake(bytes calldata payload)
        internal
        pure
        returns (uint256 index, uint256 tokenId, IMetadexCLPositionManager.MintParams memory params)
    {
        assertLength(payload, STAKE_LENGTH);

        (index, tokenId) = readKey(payload);
        assembly ("memory-safe") {
            mstore(add(params, 0xa0), calldataload(add(payload.offset, 13)))
            mstore(add(params, 0xc0), calldataload(add(payload.offset, 45)))
            mstore(add(params, 0xe0), calldataload(add(payload.offset, 77)))
            mstore(add(params, 0x100), calldataload(add(payload.offset, 109)))
        }
    }

    /**
     * @notice Decodes a swap against the pool.
     * @param payload The tight-packed payload.
     * @return zeroForOne True to sell token0 for token1.
     * @return amountIn The amount of the input token, taken from the buffer.
     * @return sqrtPriceLimitX96 The price the swap stops at.
     * @return minAmountOut The minimum amount of the output token.
     */
    function decodeSwapViaPool(bytes calldata payload)
        internal
        pure
        returns (bool zeroForOne, uint256 amountIn, uint160 sqrtPriceLimitX96, uint256 minAmountOut)
    {
        assertLength(payload, SWAP_VIA_POOL_LENGTH);
        zeroForOne = readBool(payload, 0);

        assembly ("memory-safe") {
            amountIn := calldataload(add(payload.offset, 1))
            sqrtPriceLimitX96 := shr(96, calldataload(add(payload.offset, 33)))
            minAmountOut := calldataload(add(payload.offset, 53))
        }
    }

    /**
     * @notice Decodes a swap on a router.
     * @param payload The tight-packed payload.
     * @return router The router that executes the swap.
     * @return amountIn The amount of the input token, taken from the buffer.
     * @return zeroForOne True to sell token0 for token1.
     * @return minAmountOut The minimum amount of the output token.
     * @return data The calldata for the router.
     */
    function decodeSwapViaRouter(bytes calldata payload)
        internal
        pure
        returns (address router, uint256 amountIn, bool zeroForOne, uint256 minAmountOut, bytes calldata data)
    {
        if (payload.length <= SWAP_VIA_ROUTER_LENGTH) revert InvalidPayload();

        assembly ("memory-safe") {
            router := shr(96, calldataload(payload.offset))
            amountIn := calldataload(add(payload.offset, 20))
            minAmountOut := calldataload(add(payload.offset, 53))
            data.offset := add(payload.offset, SWAP_VIA_ROUTER_LENGTH)
            data.length := sub(payload.length, SWAP_VIA_ROUTER_LENGTH)
        }
        zeroForOne = readBool(payload, 52);
    }

    /**
     * @notice Decodes a whole-queue clear.
     * @param payload The tight-packed payload.
     * @return isToken0 True for the token0 vault.
     * @return isDeposit True for the deposit queue.
     */
    function decodeQueue(bytes calldata payload) internal pure returns (bool isToken0, bool isDeposit) {
        assertLength(payload, QUEUE_LENGTH);

        isToken0 = readBool(payload, 0);
        isDeposit = readBool(payload, 1);
    }

    /**
     * @notice Decodes the queue and the controller count of a controller list payload.
     * @param payload The tight-packed payload.
     * @return isToken0 True for the token0 vault.
     * @return isDeposit True for the deposit queue.
     * @return count The number of controllers.
     */
    function decodeControllers(bytes calldata payload)
        internal
        pure
        returns (bool isToken0, bool isDeposit, uint256 count)
    {
        // Unchecked: the length check bounds the subtraction.
        unchecked {
            if (payload.length < QUEUE_LENGTH || (payload.length - QUEUE_LENGTH) % CONTROLLER_LENGTH != 0) {
                revert InvalidPayload();
            }
            count = (payload.length - QUEUE_LENGTH) / CONTROLLER_LENGTH;
        }

        isToken0 = readBool(payload, 0);
        isDeposit = readBool(payload, 1);
    }

    /**
     * @notice Decodes the core's immutables appended to the calldata in the layout of ERC-3448.
     * @return immutables The core's immutables.
     */
    function decodeCoreImmutables() internal pure returns (CoreImmutables memory immutables) {
        assembly ("memory-safe") {
            let posOfMetadataSize := sub(calldatasize(), 0x20)
            calldatacopy(immutables, sub(posOfMetadataSize, calldataload(posOfMetadataSize)), 0x120)
        }
    }

    /* //////////////////////////////////////////////////////////////
                                 HELPERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Reverts unless a payload has the length its command takes.
     * @param payload The tight-packed payload.
     * @param length The length the command takes.
     */
    function assertLength(bytes calldata payload, uint256 length) internal pure {
        if (payload.length != length) revert InvalidPayload();
    }

    /**
     * @notice Reads the range a payload names, by index and the token id it must hold.
     * @param payload The tight-packed payload.
     * @return index The index of the range.
     * @return tokenId The token id the range is expected to hold on the side the command acts on.
     */
    function readKey(bytes calldata payload) internal pure returns (uint256 index, uint256 tokenId) {
        assembly ("memory-safe") {
            index := shr(248, calldataload(payload.offset))
            tokenId := shr(160, calldataload(add(payload.offset, 1)))
        }
    }

    /**
     * @notice Reads one controller of a controller list payload.
     * @param payload The tight-packed payload.
     * @param index The index of the controller.
     * @return controller The account the record is held for.
     */
    function readController(bytes calldata payload, uint256 index) internal pure returns (address controller) {
        // Unchecked: the index is below the controller count at every caller.
        unchecked {
            uint256 offset = QUEUE_LENGTH + index * CONTROLLER_LENGTH;

            assembly ("memory-safe") {
                controller := shr(96, calldataload(add(payload.offset, offset)))
            }
        }
    }

    /**
     * @notice Reads a one-byte flag of a payload.
     * @param payload The tight-packed payload.
     * @param offset The byte the flag sits at.
     * @return flag True when the byte is non-zero.
     */
    function readBool(bytes calldata payload, uint256 offset) internal pure returns (bool flag) {
        assembly ("memory-safe") {
            flag := iszero(iszero(shr(248, calldataload(add(payload.offset, offset)))))
        }
    }
}

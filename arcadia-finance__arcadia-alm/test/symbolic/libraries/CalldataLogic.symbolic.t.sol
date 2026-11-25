/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogicExtension } from "../../utils/extensions/CalldataLogicExtension.sol";
import { CoreImmutables } from "../../../src/core/types/CoreImmutables.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";

/**
 * @notice Symbolic tests for the payload decoders of library "CalldataLogic" of the core.
 */
contract Decoders_CalldataLogic_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    CalldataLogicExtension internal calldataLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        calldataLogic = new CalldataLogicExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_decodeRange_RoundTripsWithAnyTrailingBytes(uint8 index, uint96 tokenId, bytes32 trailing)
        public
        view
    {
        // Given: A range payload as the keeper packs it, with any bytes after it.
        bytes memory payload = abi.encodePacked(index, tokenId);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeRange.selector, uint256(0x20), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        (uint256 index_, uint256 tokenId_) = abi.decode(result, (uint256, uint256));
        assertEq(index_, index);
        assertEq(tokenId_, tokenId);
    }

    function prove_decodePosition_RoundTripsWithAnyTrailingBytes(uint96 tokenId, bytes32 trailing) public view {
        // Given: A position payload as the keeper packs it, with any bytes after it.
        bytes memory payload = abi.encodePacked(tokenId);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodePosition.selector, uint256(0x20), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: The token id comes back as it went in, and every other field is zero.
        assertTrue(success);
        IMetadexCLPositionManager.CollectParams memory params =
            abi.decode(result, (IMetadexCLPositionManager.CollectParams));
        assertEq(params.tokenId, tokenId);
        assertEq(params.recipient, address(0));
        assertEq(params.amount0Max, 0);
        assertEq(params.amount1Max, 0);
    }

    function prove_decodeDecrease_Unstaked_RoundTripsWithAnyTrailingBytes(
        uint8 index,
        uint96 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        bytes32 trailing
    ) public view {
        // Given: An unstaked decrease payload as the keeper packs it, then any bytes.
        bytes memory payload = abi.encodePacked(index, tokenId, liquidity, amount0Min, amount1Min);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeDecrease.selector, uint256(0x40), uint256(0), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in, and the penalty is never accepted.
        assertTrue(success);
        (uint256 index_, IMetadexCLPositionManager.DecreaseLiquidityParams memory params, bool acceptPenalty) =
            abi.decode(result, (uint256, IMetadexCLPositionManager.DecreaseLiquidityParams, bool));
        assertEq(index_, index);
        assertEq(params.tokenId, tokenId);
        assertEq(params.liquidity, liquidity);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
        assertEq(params.deadline, 0);
        assertFalse(acceptPenalty);
    }

    function prove_decodeDecrease_Staked_RoundTripsWithAnyTrailingBytes(
        uint8 index,
        uint96 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        bytes1 acceptPenalty,
        bytes32 trailing
    ) public view {
        // Given: A staked decrease payload as the keeper packs it, then any bytes.
        bytes memory payload = abi.encodePacked(index, tokenId, liquidity, amount0Min, amount1Min, acceptPenalty);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeDecrease.selector, uint256(0x40), uint256(1), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        (uint256 index_, IMetadexCLPositionManager.DecreaseLiquidityParams memory params, bool acceptPenalty_) =
            abi.decode(result, (uint256, IMetadexCLPositionManager.DecreaseLiquidityParams, bool));
        assertEq(index_, index);
        assertEq(params.tokenId, tokenId);
        assertEq(params.liquidity, liquidity);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
        assertEq(params.deadline, 0);
        assertEq(acceptPenalty_, acceptPenalty != 0);
    }

    function prove_decodeOpen_RoundTripsWithAnyTrailingBytes(
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        bytes32 trailing
    ) public view {
        // Given: An open payload as the keeper packs it, with any bytes after it.
        bytes memory callData;
        {
            bytes memory payload =
                abi.encodePacked(tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min);
            callData = abi.encodePacked(
                CalldataLogicExtension.decodeOpen.selector, uint256(0x20), payload.length, payload, trailing
            );
        }

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in, and every other field is zero.
        assertTrue(success);
        IMetadexCLPositionManager.MintParams memory params = abi.decode(result, (IMetadexCLPositionManager.MintParams));
        assertEq(params.token0, address(0));
        assertEq(params.token1, address(0));
        assertEq(params.tickSpacing, 0);
        assertEq(params.tickLower, tickLower);
        assertEq(params.tickUpper, tickUpper);
        assertEq(params.amount0Desired, amount0Desired);
        assertEq(params.amount1Desired, amount1Desired);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
        assertEq(params.recipient, address(0));
        assertEq(params.deadline, 0);
        assertEq(params.sqrtPriceX96, 0);
    }

    function prove_decodeIncrease_Unstaked_RoundTripsWithAnyTrailingBytes(
        uint8 index,
        uint96 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        bytes32 trailing
    ) public view {
        // Given: An unstaked increase payload as the keeper packs it, then any bytes.
        bytes memory callData;
        {
            bytes memory payload =
                abi.encodePacked(index, tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min);
            callData = abi.encodePacked(
                CalldataLogicExtension.decodeIncrease.selector,
                uint256(0x40),
                uint256(0),
                payload.length,
                payload,
                trailing
            );
        }

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in, and the penalty is never accepted.
        assertTrue(success);
        (uint256 index_, IMetadexCLPositionManager.IncreaseLiquidityParams memory params, bool acceptPenalty) =
            abi.decode(result, (uint256, IMetadexCLPositionManager.IncreaseLiquidityParams, bool));
        assertEq(index_, index);
        assertEq(params.tokenId, tokenId);
        assertEq(params.amount0Desired, amount0Desired);
        assertEq(params.amount1Desired, amount1Desired);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
        assertEq(params.deadline, 0);
        assertFalse(acceptPenalty);
    }

    function prove_decodeIncrease_Staked_RoundTripsWithAnyTrailingBytes(
        uint8 index,
        uint96 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        bytes1 acceptPenalty,
        bytes32 trailing
    ) public view {
        // Given: A staked increase payload as the keeper packs it, then any bytes.
        bytes memory callData;
        {
            bytes memory payload = abi.encodePacked(
                index, tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min, acceptPenalty
            );
            callData = abi.encodePacked(
                CalldataLogicExtension.decodeIncrease.selector,
                uint256(0x40),
                uint256(1),
                payload.length,
                payload,
                trailing
            );
        }

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        (uint256 index_, IMetadexCLPositionManager.IncreaseLiquidityParams memory params, bool acceptPenalty_) =
            abi.decode(result, (uint256, IMetadexCLPositionManager.IncreaseLiquidityParams, bool));
        assertEq(index_, index);
        assertEq(params.tokenId, tokenId);
        assertEq(params.amount0Desired, amount0Desired);
        assertEq(params.amount1Desired, amount1Desired);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
        assertEq(params.deadline, 0);
        assertEq(acceptPenalty_, acceptPenalty != 0);
    }

    function prove_decodeStake_RoundTripsWithAnyTrailingBytes(
        uint8 index,
        uint96 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        bytes32 trailing
    ) public view {
        // Given: A stake payload as the keeper packs it, with any bytes after it.
        bytes memory callData;
        {
            bytes memory payload =
                abi.encodePacked(index, tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min);
            callData = abi.encodePacked(
                CalldataLogicExtension.decodeStake.selector, uint256(0x20), payload.length, payload, trailing
            );
        }

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in, and every other field is zero.
        assertTrue(success);
        (uint256 index_, uint256 tokenId_, IMetadexCLPositionManager.MintParams memory params) =
            abi.decode(result, (uint256, uint256, IMetadexCLPositionManager.MintParams));
        assertEq(index_, index);
        assertEq(tokenId_, tokenId);
        assertEq(params.token0, address(0));
        assertEq(params.token1, address(0));
        assertEq(params.tickSpacing, 0);
        assertEq(params.tickLower, 0);
        assertEq(params.tickUpper, 0);
        assertEq(params.amount0Desired, amount0Desired);
        assertEq(params.amount1Desired, amount1Desired);
        assertEq(params.amount0Min, amount0Min);
        assertEq(params.amount1Min, amount1Min);
        assertEq(params.recipient, address(0));
        assertEq(params.deadline, 0);
        assertEq(params.sqrtPriceX96, 0);
    }

    function prove_decodeSwapViaPool_RoundTripsWithAnyTrailingBytes(
        bytes1 zeroForOne,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountOut,
        bytes32 trailing
    ) public view {
        // Given: A pool swap payload as the keeper packs it, with any bytes after it.
        bytes memory payload = abi.encodePacked(zeroForOne, amountIn, sqrtPriceLimitX96, minAmountOut);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeSwapViaPool.selector, uint256(0x20), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every field comes back as it went in.
        assertTrue(success);
        (bool zeroForOne_, uint256 amountIn_, uint256 sqrtPriceLimitX96_, uint256 minAmountOut_) =
            abi.decode(result, (bool, uint256, uint256, uint256));
        assertEq(zeroForOne_, zeroForOne != 0);
        assertEq(amountIn_, amountIn);
        assertEq(sqrtPriceLimitX96_, sqrtPriceLimitX96);
        assertEq(minAmountOut_, minAmountOut);
    }

    function prove_decodeSwapViaRouter_RoundTripsEveryField(
        address router,
        uint256 amountIn,
        bytes1 zeroForOne,
        uint256 minAmountOut,
        bytes32 data
    ) public view {
        // Given: A router swap payload as the keeper packs it, with 32 bytes of calldata.
        bytes memory payload = abi.encodePacked(router, amountIn, zeroForOne, minAmountOut, data);

        // When: Decoding it.
        (address router_, uint256 amountIn_, bool zeroForOne_, uint256 minAmountOut_, bytes memory data_) =
            calldataLogic.decodeSwapViaRouter(payload);

        // Then: Every field comes back as it went in.
        assertEq(router_, router);
        assertEq(amountIn_, amountIn);
        assertEq(zeroForOne_, zeroForOne != 0);
        assertEq(minAmountOut_, minAmountOut);
        assertEq(data_.length, 32);
        assertEq(bytes32(data_), data);
    }

    function prove_decodeQueue_RoundTripsWithAnyTrailingBytes(bytes1 isToken0, bytes1 isDeposit, bytes32 trailing)
        public
        view
    {
        // Given: A queue payload as the keeper packs it, with any bytes after it.
        bytes memory payload = abi.encodePacked(isToken0, isDeposit);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeQueue.selector, uint256(0x20), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Both flags come back as non-zero bytes.
        assertTrue(success);
        (bool isToken0_, bool isDeposit_) = abi.decode(result, (bool, bool));
        assertEq(isToken0_, isToken0 != 0);
        assertEq(isDeposit_, isDeposit != 0);
    }

    function prove_decodeControllers_CountsTwoControllersWithAnyTrailingBytes(
        bytes1 isToken0,
        bytes1 isDeposit,
        address controller0,
        address controller1,
        bytes32 trailing
    ) public view {
        // Given: A payload of two controllers as the keeper packs it, then any bytes.
        bytes memory payload = abi.encodePacked(isToken0, isDeposit, controller0, controller1);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeControllers.selector, uint256(0x20), payload.length, payload, trailing
        );

        // When: Decoding it.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Both flags come back as non-zero bytes, with a count of two.
        assertTrue(success);
        (bool isToken0_, bool isDeposit_, uint256 count) = abi.decode(result, (bool, bool, uint256));
        assertEq(isToken0_, isToken0 != 0);
        assertEq(isDeposit_, isDeposit != 0);
        assertEq(count, 2);
    }

    function prove_readController_ReadsEitherControllerWithAnyTrailingBytes(
        bytes2 queue,
        address controller0,
        address controller1,
        bool second,
        bytes32 trailing
    ) public view {
        // Given: A payload of two controllers as the keeper packs it, then any bytes.
        bytes memory payload = abi.encodePacked(queue, controller0, controller1);
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.readController.selector,
            uint256(0x40),
            uint256(second ? 1 : 0),
            payload.length,
            payload,
            trailing
        );

        // When: Reading the first or the second controller.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: It is that controller.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), uint160(second ? controller1 : controller0));
    }

    function prove_decodeCoreImmutables_ReadsTheAppendedMetadata(bytes32 arguments, CoreImmutables memory immutables)
        public
        view
    {
        // Given: Any arguments, with the immutables appended as the core delegates.
        bytes memory callData = abi.encodePacked(
            CalldataLogicExtension.decodeCoreImmutables.selector, arguments, abi.encode(immutables), uint256(0x120)
        );

        // When: Decoding the immutables.
        (bool success, bytes memory result) = address(calldataLogic).staticcall(callData);

        // Then: Every immutable comes back as it was appended.
        assertTrue(success);
        CoreImmutables memory decoded = abi.decode(result, (CoreImmutables));
        assertEq(decoded.tickSpacing, immutables.tickSpacing);
        assertEq(decoded.pool, immutables.pool);
        assertEq(decoded.token0, immutables.token0);
        assertEq(decoded.token1, immutables.token1);
        assertEq(decoded.gauge, immutables.gauge);
        assertEq(decoded.asyncVault0, immutables.asyncVault0);
        assertEq(decoded.asyncVault1, immutables.asyncVault1);
        assertEq(decoded.syncVault0, immutables.syncVault0);
        assertEq(decoded.syncVault1, immutables.syncVault1);
    }
}

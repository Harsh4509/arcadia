/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { CoreImmutables } from "../../../src/core/types/CoreImmutables.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";

contract CalldataLogicExtension {
    function decodeRange(bytes calldata payload) external pure returns (uint256 index, uint256 tokenId) {
        (index, tokenId) = CalldataLogic.decodeRange(payload);
    }

    function decodePosition(bytes calldata payload)
        external
        pure
        returns (IMetadexCLPositionManager.CollectParams memory params)
    {
        params = CalldataLogic.decodePosition(payload);
    }

    function decodeDecrease(bytes calldata payload, bool staked)
        external
        pure
        returns (uint256 index, IMetadexCLPositionManager.DecreaseLiquidityParams memory params, bool acceptPenalty)
    {
        (index, params, acceptPenalty) = CalldataLogic.decodeDecrease(payload, staked);
    }

    function decodeOpen(bytes calldata payload)
        external
        pure
        returns (IMetadexCLPositionManager.MintParams memory params)
    {
        params = CalldataLogic.decodeOpen(payload);
    }

    function decodeIncrease(bytes calldata payload, bool staked)
        external
        pure
        returns (uint256 index, IMetadexCLPositionManager.IncreaseLiquidityParams memory params, bool acceptPenalty)
    {
        (index, params, acceptPenalty) = CalldataLogic.decodeIncrease(payload, staked);
    }

    function decodeStake(bytes calldata payload)
        external
        pure
        returns (uint256 index, uint256 tokenId, IMetadexCLPositionManager.MintParams memory params)
    {
        (index, tokenId, params) = CalldataLogic.decodeStake(payload);
    }

    function decodeSwapViaPool(bytes calldata payload)
        external
        pure
        returns (bool zeroForOne, uint256 amountIn, uint160 sqrtPriceLimitX96, uint256 minAmountOut)
    {
        (zeroForOne, amountIn, sqrtPriceLimitX96, minAmountOut) = CalldataLogic.decodeSwapViaPool(payload);
    }

    function decodeSwapViaRouter(bytes calldata payload)
        external
        pure
        returns (address router, uint256 amountIn, bool zeroForOne, uint256 minAmountOut, bytes memory data)
    {
        (router, amountIn, zeroForOne, minAmountOut, data) = CalldataLogic.decodeSwapViaRouter(payload);
    }

    function decodeQueue(bytes calldata payload) external pure returns (bool isToken0, bool isDeposit) {
        (isToken0, isDeposit) = CalldataLogic.decodeQueue(payload);
    }

    function decodeControllers(bytes calldata payload)
        external
        pure
        returns (bool isToken0, bool isDeposit, uint256 count)
    {
        (isToken0, isDeposit, count) = CalldataLogic.decodeControllers(payload);
    }

    function decodeCoreImmutables() external pure returns (CoreImmutables memory immutables) {
        immutables = CalldataLogic.decodeCoreImmutables();
    }

    function assertLength(bytes calldata payload, uint256 length) external pure {
        CalldataLogic.assertLength(payload, length);
    }

    function readKey(bytes calldata payload) external pure returns (uint256 index, uint256 tokenId) {
        (index, tokenId) = CalldataLogic.readKey(payload);
    }

    function readController(bytes calldata payload, uint256 index) external pure returns (address controller) {
        controller = CalldataLogic.readController(payload, index);
    }

    function readBool(bytes calldata payload, uint256 offset) external pure returns (bool flag) {
        flag = CalldataLogic.readBool(payload, offset);
    }
}

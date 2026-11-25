/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { BalanceRouterMock } from "./mocks/BalanceRouterMock.sol";
import { CommandLogic } from "../../src/core/libraries/logic/CommandLogic.sol";
import { LockProbeRouterMock } from "./mocks/LockProbeRouterMock.sol";

/**
 * @notice Assembles the commands and payloads of one keeper plan, one appended step at a time.
 */
// forge-lint: disable-next-item(uninitialized-local, unsafe-typecast)
library Plan {
    struct Steps {
        bytes commands;
        bytes[] inputs;
    }

    function init() internal pure returns (Steps memory plan) {
        plan = Steps({ commands: "", inputs: new bytes[](0) });
    }

    function add(Steps memory plan, uint8 command, bytes memory payload) internal pure returns (Steps memory) {
        bytes[] memory inputs = new bytes[](plan.inputs.length + 1);
        for (uint256 i; i < plan.inputs.length; ++i) {
            inputs[i] = plan.inputs[i];
        }
        inputs[plan.inputs.length] = payload;

        return Steps({ commands: abi.encodePacked(plan.commands, command), inputs: inputs });
    }

    function closeRange(Steps memory plan, uint256 index, uint256 tokenId) internal pure returns (Steps memory) {
        return add(plan, CommandLogic.CLOSE_RANGE, range(index, tokenId));
    }

    function decreaseLiquidity(
        Steps memory plan,
        uint256 index,
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal pure returns (Steps memory) {
        return add(
            plan,
            CommandLogic.DECREASE_LIQUIDITY,
            abi.encodePacked(range(index, tokenId), liquidity, amount0Min, amount1Min)
        );
    }

    function collect(Steps memory plan, uint256 tokenId) internal pure returns (Steps memory) {
        return add(plan, CommandLogic.COLLECT, position(tokenId));
    }

    function unstake(
        Steps memory plan,
        uint256 index,
        uint256 tokenId,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        bool acceptPenalty
    ) internal pure returns (Steps memory) {
        return add(
            plan,
            CommandLogic.UNSTAKE,
            abi.encodePacked(range(index, tokenId), liquidity, amount0Min, amount1Min, acceptPenalty)
        );
    }

    function emergencyUnstake(Steps memory plan, uint256 index, uint256 tokenId) internal pure returns (Steps memory) {
        return add(plan, CommandLogic.EMERGENCY_UNSTAKE, range(index, tokenId));
    }

    function openRange(
        Steps memory plan,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal pure returns (Steps memory) {
        return add(
            plan,
            CommandLogic.OPEN_RANGE,
            abi.encodePacked(tickLower, tickUpper, amount0Desired, amount1Desired, amount0Min, amount1Min)
        );
    }

    function increaseLiquidity(
        Steps memory plan,
        uint256 index,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal pure returns (Steps memory) {
        return add(
            plan,
            CommandLogic.INCREASE_LIQUIDITY,
            increase(index, tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min)
        );
    }

    function stake(
        Steps memory plan,
        uint256 index,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal pure returns (Steps memory) {
        return add(
            plan, CommandLogic.STAKE, increase(index, tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min)
        );
    }

    function increaseStakedLiquidity(
        Steps memory plan,
        uint256 index,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        bool acceptPenalty
    ) internal pure returns (Steps memory) {
        return add(
            plan,
            CommandLogic.INCREASE_STAKED_LIQUIDITY,
            abi.encodePacked(
                increase(index, tokenId, amount0Desired, amount1Desired, amount0Min, amount1Min), acceptPenalty
            )
        );
    }

    function swapViaPool(
        Steps memory plan,
        bool zeroForOne,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96,
        uint256 minAmountOut
    ) internal pure returns (Steps memory) {
        return add(
            plan, CommandLogic.SWAP_VIA_POOL, abi.encodePacked(zeroForOne, amountIn, sqrtPriceLimitX96, minAmountOut)
        );
    }

    function swapViaRouter(
        Steps memory plan,
        address router,
        uint256 amountIn,
        bool zeroForOne,
        uint256 minAmountOut,
        bytes memory data
    ) internal pure returns (Steps memory) {
        return add(
            plan, CommandLogic.SWAP_VIA_ROUTER, abi.encodePacked(router, amountIn, zeroForOne, minAmountOut, data)
        );
    }

    function swapAtRate(
        Steps memory plan,
        address token0,
        address token1,
        address trampoline,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut
    ) internal returns (Steps memory) {
        LockProbeRouterMock router = new LockProbeRouterMock();
        (address tokenIn, address tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);
        bytes memory data =
            abi.encodeCall(LockProbeRouterMock.swap, (tokenIn, tokenOut, amountIn, amountOut, trampoline));
        return swapViaRouter(plan, address(router), amountIn, zeroForOne, 0, data);
    }

    function swapBalance(
        Steps memory plan,
        address router,
        address token0,
        address token1,
        address trampoline,
        bool zeroForOne,
        uint256 amountIn,
        uint256 sqrtPriceX96,
        uint256 fee
    ) internal pure returns (Steps memory) {
        (address tokenIn, address tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);
        bytes memory data =
            abi.encodeCall(BalanceRouterMock.swap, (tokenIn, tokenOut, zeroForOne, sqrtPriceX96, fee, trampoline));
        return swapViaRouter(plan, router, amountIn, zeroForOne, 0, data);
    }

    function clearRequests(Steps memory plan, bool isToken0, bool isDeposit, address[] memory controllers)
        internal
        pure
        returns (Steps memory)
    {
        return add(plan, CommandLogic.CLEAR_REQUESTS, entries(isToken0, isDeposit, controllers));
    }

    function clearAllRequests(Steps memory plan, bool isToken0, bool isDeposit) internal pure returns (Steps memory) {
        return add(plan, CommandLogic.CLEAR_ALL_REQUESTS, abi.encodePacked(isToken0, isDeposit));
    }

    function cancelRequests(Steps memory plan, bool isToken0, bool isDeposit, address[] memory controllers)
        internal
        pure
        returns (Steps memory)
    {
        return add(plan, CommandLogic.CANCEL_REQUESTS, entries(isToken0, isDeposit, controllers));
    }

    function settleRequests(Steps memory plan) internal pure returns (Steps memory) {
        return add(plan, CommandLogic.SETTLE_REQUESTS, "");
    }

    function range(uint256 index, uint256 tokenId) internal pure returns (bytes memory payload) {
        payload = abi.encodePacked(uint8(index), uint96(tokenId));
    }

    function position(uint256 tokenId) internal pure returns (bytes memory payload) {
        payload = abi.encodePacked(uint96(tokenId));
    }

    function increase(
        uint256 index,
        uint256 tokenId,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal pure returns (bytes memory payload) {
        payload = abi.encodePacked(range(index, tokenId), amount0Desired, amount1Desired, amount0Min, amount1Min);
    }

    function entries(bool isToken0, bool isDeposit, address[] memory controllers)
        internal
        pure
        returns (bytes memory payload)
    {
        payload = abi.encodePacked(isToken0, isDeposit);
        for (uint256 i; i < controllers.length; ++i) {
            payload = abi.encodePacked(payload, controllers[i]);
        }
    }

    function one(address controller) internal pure returns (address[] memory controllers) {
        controllers = new address[](1);
        controllers[0] = controller;
    }

    function two(address controller, address secondController) internal pure returns (address[] memory controllers) {
        controllers = new address[](2);
        (controllers[0], controllers[1]) = (controller, secondController);
    }

    function none() internal pure returns (address[] memory controllers) {
        controllers = new address[](0);
    }
}

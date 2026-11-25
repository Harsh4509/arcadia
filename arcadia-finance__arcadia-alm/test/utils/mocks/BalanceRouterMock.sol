/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ERC20Mock } from "./ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

// forge-lint: disable-next-item(erc20-unchecked-transfer)
contract BalanceRouterMock {
    using FixedPointMathLib for uint256;

    function swap(
        address tokenIn,
        address tokenOut,
        bool zeroForOne,
        uint256 sqrtPriceX96,
        uint256 fee,
        address recipient
    ) external {
        uint256 amountIn = ERC20Mock(tokenIn).balanceOf(msg.sender);
        ERC20Mock(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        uint256 amountOut = zeroForOne
            ? amountIn.fullMulDiv(sqrtPriceX96 * sqrtPriceX96, 1 << 192)
            : amountIn.fullMulDiv(1 << 192, sqrtPriceX96 * sqrtPriceX96);
        ERC20Mock(tokenOut).mint(recipient, amountOut - amountOut * fee / 1e6);
    }
}

/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreHandler } from "./ALMCoreHandler.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { ISwapRouter } from "../../utils/fixtures/metadex/interfaces/ISwapRouter.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Trades against the pool of "ALMCore" as a third party, and lets time pass, for the invariant suite.
 */
contract PoolHandler is BaseHandler {
    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ALMCoreExtension internal immutable ALM_CORE;
    ALMCoreHandler internal immutable CORE_HANDLER;
    ICLPool internal immutable POOL;
    ISwapRouter internal immutable SWAP_ROUTER;
    address internal immutable TRADER;
    // The band the base's pool prices are drawn from, which bounds the band of twice the spot band around the TWAP.
    uint160 internal immutable SQRT_PRICE_LOWER;
    uint160 internal immutable SQRT_PRICE_UPPER;

    // The swaps that moved the pool price.
    uint256 public ghostSwaps;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ALMCoreHandler coreHandler,
        ICLPool pool,
        ISwapRouter swapRouter,
        address trader,
        uint160 sqrtPriceLower,
        uint160 sqrtPriceUpper
    ) {
        ALM_CORE = almCore;
        CORE_HANDLER = coreHandler;
        POOL = pool;
        SWAP_ROUTER = swapRouter;
        TRADER = trader;
        SQRT_PRICE_LOWER = sqrtPriceLower;
        SQRT_PRICE_UPPER = sqrtPriceUpper;
    }

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function swapTo(uint256 sqrtPriceX96, uint256 amountIn) external countCall(this.swapTo.selector) advanceBlock {
        (uint256 lower, uint256 upper) = CLMath.getBand(ALM_CORE.meanSqrtPriceX96_(), 2 * ALM_CORE.maxSpotFromTwap_());
        lower = FixedPointMathLib.max(lower, SQRT_PRICE_LOWER);
        upper = FixedPointMathLib.min(upper, SQRT_PRICE_UPPER);
        sqrtPriceX96 = bound(sqrtPriceX96, lower, FixedPointMathLib.max(lower, upper));
        (uint160 spot,,,,,) = POOL.slot0();
        if (sqrtPriceX96 == spot) return;
        bool zeroForOne = sqrtPriceX96 < spot;
        (address tokenIn, address tokenOut) =
            zeroForOne ? (POOL.token0(), POOL.token1()) : (POOL.token1(), POOL.token0());
        {
            uint256 toTarget = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(uint160(sqrtPriceX96), spot, POOL.liquidity(), true)
                : SqrtPriceMath.getAmount1Delta(spot, uint160(sqrtPriceX96), POOL.liquidity(), true);
            amountIn = bound(amountIn, 1, FixedPointMathLib.max(toTarget, 1));
        }
        ERC20Mock(tokenIn).mint(TRADER, amountIn);
        CORE_HANDLER.trackFairShares();

        vm.startPrank(TRADER);
        ERC20Mock(tokenIn).approve(address(SWAP_ROUTER), amountIn);
        try SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: POOL.tickSpacing(),
                recipient: TRADER,
                deadline: vm.getBlockTimestamp(),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: uint160(sqrtPriceX96)
            })
        ) {
            ghostSwaps++;
        } catch (bytes memory reason) {
            _recordRevert(this.swapTo.selector, reason);
        }
        ERC20Mock(tokenIn).approve(address(SWAP_ROUTER), 0);
        vm.stopPrank();
    }

    function elapse(uint256 seconds_) external countCall(this.elapse.selector) advanceBlock {
        seconds_ = bound(seconds_, 1, Constants.TWAP_WINDOW);
        CORE_HANDLER.trackFairShares();
        vm.roll(vm.getBlockNumber() + (seconds_ + BLOCK_TIME - 1) / BLOCK_TIME);
        vm.warp(vm.getBlockTimestamp() + seconds_);
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _afterAction() internal override {
        CORE_HANDLER.checkMonotone();
    }
}

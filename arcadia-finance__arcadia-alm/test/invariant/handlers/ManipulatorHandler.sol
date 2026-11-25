/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { BaseHandler } from "./BaseHandler.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { ISwapRouter } from "../../utils/fixtures/metadex/interfaces/ISwapRouter.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { Snapshot, SnapshotLib } from "../../../src/vaults/types/Snapshot.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Moves the pool price, acts through the core or a sync vault, restores the price and ghosts the value at it.
 */
// forge-lint: disable-next-item(calls-loop, missing-zero-check, uninitialized-local, unsafe-typecast, unused-return)
contract ManipulatorHandler is BaseHandler {
    using ALMCoreViewLogic for IALMCore;
    using ALMCoreViewLogic for bytes32[];
    using FixedPointMathLib for uint256;
    using SnapshotLib for IALMCore;

    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // The token balance the actor is topped up to before every round trip.
    uint256 internal constant ACTOR_FUNDING = 1e30;

    uint256 internal constant MAX_PUSH = 1e18;

    // The bounds the price-moving leg of a round trip is drawn from.
    uint256 internal constant MIN_PUSH = 1e15;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    uint256 public ghostRoundTrips;
    uint256 public ghostUnrestored;
    uint256 public ghostActorGains;
    uint256 public ghostStayerLosses;
    uint256 public ghostSharesMinted;
    uint256 public ghostSharesBurned;

    /* //////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    ////////////////////////////////////////////////////////////// */

    constructor(
        ALMCoreExtension almCore,
        ISwapRouter swapRouter,
        address actor,
        address syncVault0,
        address syncVault1
    ) {
        ALM_CORE = almCore;
        SYNC_VAULT0 = ALMVaultSync(syncVault0);
        SYNC_VAULT1 = ALMVaultSync(syncVault1);
        SWAP_ROUTER = swapRouter;
        POOL = ICLPool(almCore.pool_());
        TOKEN0 = almCore.token0();
        TOKEN1 = almCore.token1();
        TICK_SPACING = almCore.tickSpacing();
        ACTOR = actor;
    }

    /* //////////////////////////////////////////////////////////////
                               IMMUTABLES
    ////////////////////////////////////////////////////////////// */

    int24 internal immutable TICK_SPACING;
    address internal immutable ACTOR;
    address internal immutable TOKEN0;
    address internal immutable TOKEN1;
    ICLPool internal immutable POOL;
    ISwapRouter internal immutable SWAP_ROUTER;
    ALMCoreExtension internal immutable ALM_CORE;
    ALMVaultSync internal immutable SYNC_VAULT0;
    ALMVaultSync internal immutable SYNC_VAULT1;

    /* //////////////////////////////////////////////////////////////
                                 ACTIONS
    ////////////////////////////////////////////////////////////// */

    function roundTrip(uint256 amountIn, uint256 amount, bool zeroForOne, uint256 mode)
        external
        countCall(this.roundTrip.selector)
    {
        vm.roll(vm.getBlockNumber() + 1);
        vm.warp(vm.getBlockTimestamp() + 2);
        _fundActor();
        uint160 sqrtPriceBefore = _sqrtPriceX96();
        uint256 perShareBefore = _perShareValue();
        uint256 valueBefore = _actorValue();

        _pushPrice(zeroForOne, bound(amountIn, MIN_PUSH, MAX_PUSH));
        bool acted = _act(amount, bound(mode, 0, 3));
        _restorePrice(sqrtPriceBefore);

        if (_sqrtPriceX96() != sqrtPriceBefore) {
            ++ghostUnrestored;
            return;
        }

        if (!acted) return;
        ++ghostRoundTrips;
        if (_actorValue() > valueBefore) ++ghostActorGains;
        if (_perShareValue() < perShareBefore) ++ghostStayerLosses;
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _act(uint256 shares, uint256 mode) internal returns (bool acted) {
        uint256 balance = ALM_CORE.balanceOf(ACTOR);
        uint256 supply = ALM_CORE.totalSupply();
        if (mode > 1) return _actThroughVault(shares, mode == 2, balance);

        if (mode == 0 || balance == 0) {
            shares = bound(shares, supply / 10 + 1, supply / 2 + 1);
            vm.prank(ACTOR);
            try ALM_CORE.mint(shares, ACTOR) {
                ghostSharesMinted += shares;
                acted = true;
            } catch (bytes memory reason) {
                _recordRevert(this.roundTrip.selector, reason);
            }
        } else {
            shares = bound(shares, 1, balance);
            vm.prank(ACTOR);
            try ALM_CORE.burn(shares, ACTOR, ACTOR) {
                ghostSharesBurned += shares;
                acted = true;
            } catch (bytes memory reason) {
                _recordRevert(this.roundTrip.selector, reason);
            }
        }
    }

    function _actThroughVault(uint256 amount, bool isDeposit, uint256 balance) internal returns (bool acted) {
        ALMVaultSync vault = amount % 2 == 0 ? SYNC_VAULT0 : SYNC_VAULT1;
        vm.prank(ACTOR);
        if (isDeposit || balance == 0) {
            try vault.deposit(bound(amount, 1, ACTOR_FUNDING / 2), ACTOR) returns (uint256 shares) {
                ghostSharesMinted += shares;
                acted = true;
            } catch (bytes memory reason) {
                _recordRevert(this.roundTrip.selector, reason);
            }
        } else {
            uint256 shares = bound(amount, 1, balance);
            try vault.redeem(shares, ACTOR, ACTOR) {
                ghostSharesBurned += shares;
                acted = true;
            } catch (bytes memory reason) {
                _recordRevert(this.roundTrip.selector, reason);
            }
        }
    }

    function _fundActor() internal {
        deal(TOKEN0, ACTOR, ACTOR_FUNDING);
        deal(TOKEN1, ACTOR, ACTOR_FUNDING);

        vm.startPrank(ACTOR);
        IERC20(TOKEN0).approve(address(ALM_CORE), type(uint256).max);
        IERC20(TOKEN1).approve(address(ALM_CORE), type(uint256).max);
        IERC20(TOKEN0).approve(address(SWAP_ROUTER), type(uint256).max);
        IERC20(TOKEN1).approve(address(SWAP_ROUTER), type(uint256).max);
        IERC20(TOKEN0).approve(address(SYNC_VAULT0), type(uint256).max);
        IERC20(TOKEN1).approve(address(SYNC_VAULT1), type(uint256).max);
        vm.stopPrank();
    }

    function _pushPrice(bool zeroForOne, uint256 amountIn) internal {
        (address tokenIn, address tokenOut) = zeroForOne ? (TOKEN0, TOKEN1) : (TOKEN1, TOKEN0);
        uint160 limit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        _swap(tokenIn, tokenOut, amountIn, limit);
    }

    function _restorePrice(uint160 sqrtPriceLimitX96) internal {
        uint160 sqrtPriceX96 = _sqrtPriceX96();
        if (sqrtPriceX96 == sqrtPriceLimitX96) return;
        (address tokenIn, address tokenOut) = sqrtPriceX96 < sqrtPriceLimitX96 ? (TOKEN1, TOKEN0) : (TOKEN0, TOKEN1);

        _swap(tokenIn, tokenOut, IERC20(tokenIn).balanceOf(ACTOR), sqrtPriceLimitX96);
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint160 sqrtPriceLimitX96) internal {
        vm.prank(ACTOR);
        SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: TICK_SPACING,
                recipient: ACTOR,
                deadline: vm.getBlockTimestamp(),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: sqrtPriceLimitX96
            })
        );
    }

    function _actorValue() internal view returns (uint256 value) {
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(address(POOL), address(this));
        PricedRange[] memory ranges = snapshot.ranges;
        uint256 balance = ALM_CORE.balanceOf(ACTOR);

        // A burn takes each range's pro-rata liquidity, unstaked side first, each position rounding down its amounts.
        PricedRange[] memory sides = new PricedRange[](2 * ranges.length);
        for (uint256 i; i < ranges.length; ++i) {
            uint128 owed = uint128(uint256(ranges[i].liquidity).fullMulDiv(balance, snapshot.supply));
            uint128 taken = owed < ranges[i].unstakedLiquidity ? owed : ranges[i].unstakedLiquidity;
            (sides[2 * i].sqrtPriceLowerX96, sides[2 * i].sqrtPriceUpperX96, sides[2 * i].liquidity) =
            (ranges[i].sqrtPriceLowerX96, ranges[i].sqrtPriceUpperX96, taken);
            (sides[2 * i + 1].sqrtPriceLowerX96, sides[2 * i + 1].sqrtPriceUpperX96, sides[2 * i + 1].liquidity) =
            (ranges[i].sqrtPriceLowerX96, ranges[i].sqrtPriceUpperX96, owed - taken);
        }
        (uint256 claim0, uint256 claim1) = _holdings(
            sides,
            _sqrtPriceX96(),
            (snapshot.buffer0 + snapshot.fees0).fullMulDiv(balance, snapshot.supply),
            (snapshot.buffer1 + snapshot.fees1).fullMulDiv(balance, snapshot.supply)
        );

        value = _spotValue(IERC20(TOKEN0).balanceOf(ACTOR) + claim0, IERC20(TOKEN1).balanceOf(ACTOR) + claim1);
    }

    function _perShareValue() internal view returns (uint256 value) {
        uint160 sqrtPriceX96 = _sqrtPriceX96();
        Snapshot memory snapshot = IALMCore(address(ALM_CORE)).getSnapshot(address(POOL), address(this));
        (uint256 amount0, uint256 amount1) = _holdings(
            snapshot.ranges, sqrtPriceX96, snapshot.buffer0 + snapshot.fees0, snapshot.buffer1 + snapshot.fees1
        );

        value = _spotValue(amount0, amount1).fullMulDiv(1e18, ALM_CORE.totalSupply());
    }

    function _spotValue(uint256 amount0, uint256 amount1) internal view returns (uint256 value) {
        uint256 sqrtPrice = _sqrtPriceX96();

        value = amount1 + amount0.fullMulDiv(sqrtPrice, 1 << 96).fullMulDiv(sqrtPrice, 1 << 96);
    }

    function _sqrtPriceX96() internal view returns (uint160 sqrtPrice) {
        (sqrtPrice,,,,,) = POOL.slot0();
    }
}

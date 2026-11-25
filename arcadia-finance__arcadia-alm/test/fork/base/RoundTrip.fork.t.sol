/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { Base_Fork_Test } from "./_Base.fork.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { IERC20 } from "@forge-std/interfaces/IERC20.sol";
import { Plan } from "../../utils/Plan.sol";

/**
 * @notice End-to-end fork tests of contract "ALMVaultAsync": request, settle and claim, in and back out, on Base.
 */
contract RoundTrip_Base_Fork_Test is Base_Fork_Test {
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_roundTrip_RequestClearAndClaim(
        uint256 assets,
        bool isToken0,
        uint256 maxShortfallBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A core worth 100k USDC of each token, in its buffer.
        seedCore(CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false), 100_000e6);

        // And: A deposit request of 10 USDC to 100k USDC of value.
        ALMVaultAsync vault = isToken0 ? asyncVault0 : asyncVault1;
        IERC20 asset = isToken0 ? token0 : token1;
        assets = bound(
            assets,
            isToken0 ? CLMath.convert(sqrtPriceX96(pool), false, 10e6, false) : 10e6,
            isToken0 ? CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false) : 100_000e6
        );
        deal(address(asset), depositor, assets);
        vm.startPrank(depositor);
        asset.approve(address(vault), assets);
        vault.requestDeposit(assets, depositor, depositor);
        vm.stopPrank();

        // And: The value of a share and of a wei of USDC in the asset.
        uint256 oneShare =
            (almCore.bufferAmount1() + CLMath.convert(sqrtPriceX96(pool), true, almCore.bufferAmount0(), false))
                / almCore.totalSupply();
        if (isToken0) oneShare = CLMath.convert(sqrtPriceX96(pool), false, oneShare, false);
        uint256 token1Wei = isToken0 ? CLMath.convert(sqrtPriceX96(pool), false, 1, false) + 1 : 0;

        // And: Plan limits above a clear's rounding loss.
        setPlanLimits(maxShortfallBps, maxSwapCostBps, 1, 0, 0);

        // When: The keeper clears it, the depositor claims, redeems all its shares, the keeper clears, it claims.
        runPlan(Plan.init().clearAllRequests(isToken0, true).settleRequests());
        vm.startPrank(depositor);
        uint256 shares = vault.deposit(assets, depositor);
        almCore.approve(address(vault), shares);
        vault.requestRedeem(shares, depositor, depositor);
        vm.stopPrank();
        runPlan(Plan.init().clearAllRequests(isToken0, false).settleRequests());
        vm.prank(depositor);
        uint256 returned = vault.redeem(shares, depositor, depositor);

        // Then: The depositor holds no shares, and got back at most what it paid.
        assertGt(shares, 0);
        assertEq(almCore.balanceOf(depositor), 0);
        assertEq(asset.balanceOf(depositor), returned);
        assertLe(returned, assets);

        // And: It lost at most a share, a wei of USDC per conversion, a wei of asset.
        assertGe(returned + oneShare + 1 + 2 * token1Wei + 1, assets);
    }
}

/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { IMetadexCLPositionManager } from "../../../src/interfaces/IMetadexCLPositionManager.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SafeTransferLib } from "@solady/utils/SafeTransferLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "mint" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract Mint_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_mint_InvalidRecipient(PoolState memory poolState, uint256 shares) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Minting to the zero address.
        // Then: It reverts.
        vm.expectRevert(BaseCore.InvalidRecipient.selector);
        almCore.mint(shares, address(0));
    }

    function testFuzz_Revert_mint_ZeroShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price, and a seeded vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(receiver != address(0));
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // When: Calling mint() for zero shares.
        // Then: It reverts.
        vm.expectRevert(ALMCore.ZeroShares.selector);
        almCore.mint(0, receiver);
    }

    function testFuzz_Revert_mint_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price, and a seeded vault that is paused.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(receiver != address(0));
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        vm.prank(factory);
        almCore.pause();

        // And: A non-zero amount of shares.
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ALMCore.Paused.selector);
        almCore.mint(shares, receiver);
    }

    function testFuzz_Revert_mint_NotInitialized(PoolState memory poolState, uint256 shares, address receiver) public {
        // Given: A pool with depth at a fuzzed price, and a vault never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(receiver != address(0));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ALMCore.NotInitialized.selector);
        almCore.mint(shares, receiver);
    }

    function testFuzz_Revert_mint_TotalCapExceeded(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        address receiver
    ) public {
        // Given: A pool at a fuzzed price, a seeded vault with its total cap at supply.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(receiver != address(0));
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        vm.prank(factory);
        almCore.lowerTotalCap(coreState.supply);
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        almCore.mint(shares, receiver);
    }

    function testFuzz_Revert_mint_PerUserCapExceeded(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 cap,
        address receiver
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(receiver != address(0) && receiver != address(almCore));
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A funded caller minting up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(address(this), Constants.MAX_FUZZED_AMOUNT);
        token1.mint(address(this), Constants.MAX_FUZZED_AMOUNT);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // And: A per user cap under the mint.
        vm.prank(factory);
        almCore.setPerUserCap(bound(cap, 0, shares - 1));

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.mint(shares, receiver);
    }

    function testFuzz_Revert_mint_PerUserCapExceeded_PendingShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 pending,
        uint256 cap
    ) public {
        // Given: A pool with depth at a fuzzed price, and a seeded vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A funded caller minting up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(address(this), Constants.MAX_FUZZED_AMOUNT);
        token1.mint(address(this), Constants.MAX_FUZZED_AMOUNT);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // And: A receiver with pending shares, and a per user cap fitting the mint alone.
        pending = bound(pending, 1, type(uint96).max);
        almCore.setPendingShares(controller, pending);
        vm.prank(factory);
        almCore.setPerUserCap(bound(cap, shares, shares + pending - 1));

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.mint(shares, controller);
    }

    function testFuzz_Revert_mint_PerUserCapExceeded_HeldShares(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 cap,
        address receiver
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.assume(receiver != address(0) && receiver != address(almCore));
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);

        // And: A funded caller minting up to half the supply, which the tick room holds.
        shares = bound(shares, 1, FixedPointMathLib.max(1, coreState.supply / 2));
        token0.mint(address(this), Constants.MAX_FUZZED_AMOUNT);
        token1.mint(address(this), Constants.MAX_FUZZED_AMOUNT);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // And: A receiver already holding as many shares as the mint.
        almCore.mintShares(receiver, shares);

        // And: A per user cap fitting either alone but not both.
        vm.prank(factory);
        almCore.setPerUserCap(bound(cap, shares, 2 * shares - 1));

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.mint(shares, receiver);
    }

    function testFuzz_Revert_mint_PriceDeviation(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxSpotFromTwap
    ) public {
        // Given: A pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A trade a tick spacing off the TWAP.
        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);

        // And: A band between spot and the TWAP narrower than spot's distance from it.
        setSpotFromTwap(outsideBand(maxSpotFromTwap, spotFromTwap(false)));
        shares = bound(shares, 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Calling mint().
        // Then: It reverts.
        vm.expectRevert(ConfigLib.PriceDeviation.selector);
        almCore.mint(shares, users.unprivilegedAddress);
    }

    function testFuzz_Revert_mint_TransferFromFailed(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A mint up to the supply that pays for the range, from no approval.
        shares = bound(shares, 1, coreState.supply);

        // When: Calling mint().
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(SafeTransferLib.TransferFromFailed.selector);
        almCore.mint(shares, users.unprivilegedAddress);
    }

    function testFuzz_Success_mint_NeverChargesAboveTheProRataClaim(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Shares up to the supply, a doubling the ranges' tick room holds.
        shares = bound(shares, 1, coreState.supply);

        // And: The pro-rata claim rounded up, plus the manager's extra unit and wei.
        uint256 supply = almCore.totalSupply();
        uint256 expected0;
        uint256 expected1;
        Range memory staged = almCore.getRange(range.index);
        uint128 owed = uint128(
            (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity).fullMulDivUp(shares, supply)
        );
        (expected0, expected1) = amountsRoundedUp(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, owed + 1);
        (expected0, expected1) = (expected0 + 1, expected1 + 1);
        expected0 += almCore.bufferAmount0().fullMulDivUp(shares, supply);
        expected1 += almCore.bufferAmount1().fullMulDivUp(shares, supply);

        // When: Calling mint().
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        (uint256 amount0, uint256 amount1) = almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The caller paid no more than its pro-rata claim.
        assertLe(amount0, expected0);
        assertLe(amount1, expected1);

        // And: It holds the shares it minted, and the supply grew by them.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertEq(almCore.totalSupply(), supply + shares);
    }

    function testFuzz_Success_mint_ExemptPastTheCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A fuzzed pool, a seeded vault, a zero cap and an exempt receiver.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        vm.startPrank(factory);
        almCore.setPerUserCap(0);
        almCore.setCapExempt(users.unprivilegedAddress, true);
        vm.stopPrank();

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: It is not checked.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_mint_MakesNoApproval(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        shares = bound(shares, 2, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        vm.expectCall(address(token0), abi.encodeWithSelector(token0.approve.selector, address(POSITION_MANAGER)), 0);
        vm.expectCall(address(token1), abi.encodeWithSelector(token1.approve.selector, address(POSITION_MANAGER)), 0);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The position manager pulled the legs on the core's deployment allowance.
        assertEq(token0.allowance(address(almCore), address(POSITION_MANAGER)), type(uint256).max);
        assertEq(token1.allowance(address(almCore), address(POSITION_MANAGER)), type(uint256).max);
    }

    function testFuzz_Success_mint_ScalesEveryRangeOnTheUnstakedSibling(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding two ranges.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(second, poolState, false);
        setRangeState(second);

        // And: Shares up to the supply, and each range's claim before the mint, up.
        shares = bound(shares, 2, coreState.supply);
        Range memory rangeBefore = almCore.getRange(range.index);
        Range memory secondBefore = almCore.getRange(second.index);
        uint128 unstakedBefore = positionLiquidity(rangeBefore.unstakedTokenId);
        uint128 secondUnstakedBefore = positionLiquidity(secondBefore.unstakedTokenId);
        uint256 supply = almCore.totalSupply();
        uint256 expected = (uint256(unstakedBefore) + rangeBefore.stakedLiquidity).fullMulDivUp(shares, supply);
        uint256 expectedSecond =
            (uint256(secondUnstakedBefore) + secondBefore.stakedLiquidity).fullMulDivUp(shares, supply);

        // When: Calling mint().
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The staked legs did not move.
        Range memory rangeAfter = almCore.getRange(range.index);
        Range memory secondAfter = almCore.getRange(second.index);
        assertEq(rangeAfter.stakedLiquidity, rangeBefore.stakedLiquidity);
        assertEq(secondAfter.stakedLiquidity, secondBefore.stakedLiquidity);

        // And: Both unstaked legs grew by their share, over by at most a wei's liquidity.
        assertGe(positionLiquidity(rangeAfter.unstakedTokenId) - unstakedBefore, expected);
        assertGe(positionLiquidity(secondAfter.unstakedTokenId) - secondUnstakedBefore, expectedSecond);
        assertLe(
            positionLiquidity(rangeAfter.unstakedTokenId) - unstakedBefore - expected,
            mintOvershoot(sqrtPriceX96(pool), rangeBefore.tickLower, rangeBefore.tickUpper)
        );
        assertLe(
            positionLiquidity(secondAfter.unstakedTokenId) - secondUnstakedBefore - expectedSecond,
            mintOvershoot(sqrtPriceX96(pool), secondBefore.tickLower, secondBefore.tickUpper)
        );
    }

    function testFuzz_Success_mint_NeverCallsTheGauge(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(
            bound(
                range.liquidityStaked,
                Constants.MIN_FUZZED_LIQUIDITY,
                liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY) / 4
            )
        );

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.deposit.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.withdraw.selector), 0);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The staked sibling is untouched.
        assertEq(almCore.getRange(range.index).stakedTokenId, range.stakedTokenId);
        assertEq(almCore.getRange(range.index).stakedLiquidity, positionLiquidity(range.stakedTokenId));
    }

    function testFuzz_Success_mint_RefundsLeftover(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: Nothing the position manager left unconsumed stays behind unaccounted.
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1());
    }

    function testFuzz_Success_mint_RefundsWhatTheRangesLeftInBothTokens(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        shares = bound(shares, 1, coreState.supply);

        // And: A caller that funded and approved more than a mint up to the supply pulls.
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // When: Calling mint().
        // Then: No token transfer moves a zero amount.
        address caller = users.unprivilegedAddress;
        vm.expectCall(address(token0), abi.encodeCall(token0.transferFrom, (caller, address(almCore), 0)), 0);
        vm.expectCall(address(token1), abi.encodeCall(token1.transferFrom, (caller, address(almCore), 0)), 0);
        vm.expectCall(address(token0), abi.encodeCall(token0.transferFrom, (address(almCore), address(pool), 0)), 0);
        vm.expectCall(address(token1), abi.encodeCall(token1.transferFrom, (address(almCore), address(pool), 0)), 0);
        vm.expectCall(address(token0), abi.encodeCall(token0.transfer, (caller, 0)), 0);
        vm.expectCall(address(token1), abi.encodeCall(token1.transfer, (caller, 0)), 0);
        (uint256 amount0, uint256 amount1) = almCore.mint(shares, caller);
        vm.stopPrank();

        // And: The caller got back what the ranges left, keeping all but what it paid.
        assertEq(token0.balanceOf(users.unprivilegedAddress), Constants.MAX_FUZZED_AMOUNT - amount0);
        assertEq(token1.balanceOf(users.unprivilegedAddress), Constants.MAX_FUZZED_AMOUNT - amount1);
    }

    function testFuzz_Success_mint_RefundsTheToken0ThePositionManagerLeft(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price near the low end of the band.
        uint256 low = uint256(TickMath.getSqrtPriceAtTick(-bandTick(TICK_SPACING))) * 1e3;
        poolState.sqrtPrice = bound(poolState.sqrtPrice, low, low * 1e3);
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A narrow range around spot with a large unstaked leg and no staked leg.
        givenValidRangeState(range, poolState, true, false);
        int24 tickSpacing = poolState.tickSpacing;
        int24 above = (poolState.tickCurrent + tickSpacing) / tickSpacing;
        range.tickUpper = int24(bound(range.tickUpper / tickSpacing, above, above + 10)) * tickSpacing;
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A funded caller minting at least half the supply.
        shares = bound(shares, FixedPointMathLib.max(coreState.supply / 2, 1), coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);

        // When: Calling mint().
        (uint256 amount0, uint256 amount1) = almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The caller got back every token0 the core did not keep.
        assertEq(token0.balanceOf(users.unprivilegedAddress), Constants.MAX_FUZZED_AMOUNT - amount0);
        assertEq(token1.balanceOf(users.unprivilegedAddress), Constants.MAX_FUZZED_AMOUNT - amount1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
    }

    function testFuzz_Success_mint_MovesNoTokenItOwesNothingIn(
        PoolState memory poolState,
        CoreState memory coreState,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded core with no ranges.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, 0, 0, 0);
        setCoreState(coreState);

        // And: A token0-only buffer, and a caller that funded and approved token0 only.
        almCore.setBuffers(coreState.buffer0, 0);
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        uint256 expected0 = coreState.buffer0.fullMulDivUp(shares, coreState.supply);

        // When: Calling mint().
        // Then: Token1 does not move, not even in an empty transfer.
        vm.expectCall(address(token1), abi.encodeWithSelector(token1.transfer.selector), 0);
        vm.expectCall(address(token1), abi.encodeWithSelector(token1.transferFrom.selector), 0);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Mint(users.unprivilegedAddress, users.unprivilegedAddress, shares, expected0, 0);
        (uint256 amount0, uint256 amount1) = almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: Only token0 was paid, into the buffer.
        assertEq(amount0, expected0);
        assertEq(amount1, 0);
        assertEq(almCore.bufferAmount0(), coreState.buffer0 + amount0);
        assertEq(almCore.bufferAmount1(), 0);
    }

    function testFuzz_Success_mint_SkipsARangeOwedNoLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price, and a seeded core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, 0, 0, 0);
        setCoreState(coreState);

        // And: A range holding no liquidity on either side.
        givenValidRangeState(range, poolState, false);
        (range.liquidity, range.liquidityStaked) = (0, 0);
        almCore.pushRange(stageRange(address(almCore), range));
        shares = bound(shares, 1, coreState.supply);

        // When: Calling mint().
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        vm.expectCall(
            address(POSITION_MANAGER), abi.encodeWithSelector(IMetadexCLPositionManager.increaseLiquidity.selector), 0
        );
        (uint256 amount0, uint256 amount1) = almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The range still holds no liquidity.
        Range memory rangeAfter = almCore.getRange(0);
        assertEq(positionLiquidity(rangeAfter.unstakedTokenId), 0);
        assertEq(rangeAfter.stakedLiquidity, 0);

        // And: The caller paid the buffer's share only, into the buffer.
        assertEq(amount0, coreState.buffer0.fullMulDivUp(shares, coreState.supply));
        assertEq(amount1, coreState.buffer1.fullMulDivUp(shares, coreState.supply));
        assertEq(almCore.bufferAmount0(), coreState.buffer0 + amount0);
        assertEq(almCore.bufferAmount1(), coreState.buffer1 + amount1);
    }

    function testFuzz_Success_mint_CreditsRewardsToReceiverBeforeTheMint(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 sharesAgain,
        uint256 earned
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A receiver holding up to the supply, a second such mint fitting the room.
        token0.mint(users.unprivilegedAddress, 2 * Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, 2 * Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(bound(shares, 1, coreState.supply), users.unprivilegedAddress);
        vm.stopPrank();

        // And: Emissions reported before the second mint, at least what credits a wei.
        uint256 supply = almCore.totalSupply();
        uint256 balance = almCore.balanceOf(users.unprivilegedAddress);
        uint256 bps = almCore.protocolEmissionFeeBps_();
        uint256 least = FixedPointMathLib.fullMulDivUp(
            FixedPointMathLib.fullMulDivUp(FixedPointMathLib.divUp(1e18, balance), supply, 1e18),
            ConfigLib.BPS_DENOMINATOR,
            ConfigLib.BPS_DENOMINATOR - bps
        );

        // And: Below what saturates the reward per share.
        uint256 ceiling = FixedPointMathLib.min(
            Constants.MAX_FUZZED_AMOUNT, FixedPointMathLib.fullMulDiv(supply, type(uint128).max, 1e18)
        );
        earned = bound(earned, FixedPointMathLib.min(least, ceiling), ceiling);
        mockEarned(gauge, address(almCore), earned);

        // And: The accumulator the net emissions raise, and the reward that credits.
        uint256 raised = almCore.rewardPerShare_()
            + FixedPointMathLib.fullMulDiv(earned - earned * bps / ConfigLib.BPS_DENOMINATOR, 1e18, supply);
        uint256 pendingBefore = almCore.getPendingReward(users.unprivilegedAddress)
            + balance.fullMulDiv(raised - almCore.getRewardSnapshot(users.unprivilegedAddress), 1e18);

        // When: Calling mint() again for the receiver, up to the supply within the cap.
        sharesAgain = bound(sharesAgain, 1, FixedPointMathLib.min(coreState.supply, almCore.totalCap_() - supply));
        vm.prank(users.unprivilegedAddress);
        almCore.mint(sharesAgain, users.unprivilegedAddress);

        // Then: The reward is credited at the balance the receiver held before it.
        assertEq(almCore.getPendingReward(users.unprivilegedAddress), pendingBefore);

        // And: The receiver's snapshot is the accumulator raised by the emissions.
        assertEq(almCore.getRewardSnapshot(users.unprivilegedAddress), raised);
    }

    function testFuzz_Success_mint_ChargesTheShareOfUncollectedFees(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint16 feeBps
    ) public {
        // Given: A pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A protocol share of every collection.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: A range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A trade ten spacings through the range and back, leaving fees on its leg.
        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickCurrent - 10 * poolState.tickSpacing);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickCurrent - 10 * poolState.tickSpacing);
        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickCurrent);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickCurrent);
        (uint256 gross0, uint256 gross1) = positionFees(pool, range.unstakedTokenId);

        // And: Token0 fees of a wei or more, a hole for trades too small to earn one.
        vm.assume(gross0 > 0);
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        uint256 owed0Before = almCore.getProtocolFees0();
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, 1, coreState.supply);

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The fees stay on the position, uncollected and not accrued.
        (uint256 grossAfter0,) = positionFees(pool, range.unstakedTokenId);
        assertEq(grossAfter0, gross0);
        assertEq(almCore.getProtocolFees0(), owed0Before);

        // And: The minter paid its share of each buffer and its net fees, rounded up.
        assertEq(
            almCore.bufferAmount0() - buffer0Before,
            (buffer0Before + gross0 - gross0 * feeBps / ConfigLib.BPS_DENOMINATOR).fullMulDivUp(shares, supply)
        );
        assertEq(
            almCore.bufferAmount1() - buffer1Before,
            (buffer1Before + gross1 - gross1 * feeBps / ConfigLib.BPS_DENOMINATOR).fullMulDivUp(shares, supply)
        );
    }

    function testFuzz_Success_mint_ScalesTheDonatedLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price without a staked leg, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault holding it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A third party added liquidity to the range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));
        uint128 liquidityBefore = positionLiquidity(range.unstakedTokenId);
        assertGt(liquidityBefore, range.liquidity);
        uint256 supply = almCore.totalSupply();
        shares = bound(shares, 1, coreState.supply);
        uint256 expected = uint256(liquidityBefore).fullMulDivUp(shares, supply);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, uint128(expected));

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        (uint256 paid0, uint256 paid1) = almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The position grew pro rata to its whole liquidity, donation included.
        assertGe(positionLiquidity(range.unstakedTokenId) - liquidityBefore, expected);

        // And: The minter paid at least that liquidity's amounts and its buffer share.
        assertGe(paid0, amount0);
        assertGe(paid1, amount1);
    }

    function testFuzz_Success_mint_ToleratesNonMintableChain(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A chain the gauge cannot mint emissions on.
        setMintable(false);

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The failed claim did not revert the mint.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_mint_ManipulatedPriceLeavesNoProfit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool zeroForOne
    ) public {
        // Given: A pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: An actor funded for a tick spacing round trip and a mint up to the supply.
        int24 target =
            zeroForOne ? poolState.tickCurrent - poolState.tickSpacing : poolState.tickCurrent + poolState.tickSpacing;
        fundActorForTick(pool, users.unprivilegedAddress, target);
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);

        // And: The actor's value and the vault's value per share at spot.
        uint160 sqrtPriceBefore = sqrtPriceX96(pool);
        uint256 perShareBefore;
        {
            Range memory staged = almCore.getRange(range.index);
            (uint256 held0, uint256 held1) = amountsRoundedDown(
                sqrtPriceBefore,
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            held0 += almCore.bufferAmount0();
            held1 += almCore.bufferAmount1();
            perShareBefore = (held1 + token0ToToken1(sqrtPriceBefore, held0)).fullMulDiv(1e18, almCore.totalSupply());
        }
        uint256 valueBefore = token1.balanceOf(users.unprivilegedAddress)
            + token0ToToken1(sqrtPriceBefore, token0.balanceOf(users.unprivilegedAddress));

        // And: The actor pushed the pool price a tick spacing at its own cost.
        pushPriceToTick(pool, users.unprivilegedAddress, target);

        // When: Minting at the manipulated price and restoring the price exactly.
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();
        {
            uint256 restoreFunding = fundActorForPrice(pool, users.unprivilegedAddress, sqrtPriceBefore);
            if (sqrtPriceBefore < sqrtPriceX96(pool)) restoreFunding = token0ToToken1(sqrtPriceBefore, restoreFunding);
            restorePrice(pool, users.unprivilegedAddress, zeroForOne, sqrtPriceBefore);
            valueBefore += restoreFunding;
        }

        // Then: The round trip left the actor no better off, its claim rounded down.
        assertEq(sqrtPriceX96(pool), sqrtPriceBefore);
        Range memory stagedAfter = almCore.getRange(range.index);
        (uint256 fees0, uint256 fees1) = positionFees(pool, stagedAfter.unstakedTokenId);
        {
            (uint256 claim0, uint256 claim1) = amountsRoundedDown(
                sqrtPriceBefore,
                stagedAfter.tickLower,
                stagedAfter.tickUpper,
                uint128(
                    (uint256(positionLiquidity(stagedAfter.unstakedTokenId)) + stagedAfter.stakedLiquidity)
                    .fullMulDiv(shares, almCore.totalSupply())
                )
            );
            claim0 += token0.balanceOf(users.unprivilegedAddress)
            + (almCore.bufferAmount0() + fees0).fullMulDiv(shares, almCore.totalSupply());
            claim1 += token1.balanceOf(users.unprivilegedAddress)
            + (almCore.bufferAmount1() + fees1).fullMulDiv(shares, almCore.totalSupply());
            assertLe(claim1 + token0ToToken1(sqrtPriceBefore, claim0), valueBefore);
        }

        // And: The stayer's value per share fell by a floored wei a token at most.
        (uint256 after0, uint256 after1) = amountsRoundedDown(
            sqrtPriceBefore,
            stagedAfter.tickLower,
            stagedAfter.tickUpper,
            positionLiquidity(stagedAfter.unstakedTokenId) + stagedAfter.stakedLiquidity
        );
        after0 += almCore.bufferAmount0() + fees0;
        after1 += almCore.bufferAmount1() + fees1;
        perShareBefore = perShareBefore.zeroFloorSub(
            (FixedPointMathLib.fullMulDivUp(1, uint256(sqrtPriceBefore) * sqrtPriceBefore, 1 << 192) + 2)
            .fullMulDivUp(1e18, almCore.totalSupply())
        );
        assertGe(
            (after1 + token0ToToken1(sqrtPriceBefore, after0)).fullMulDiv(1e18, almCore.totalSupply()), perShareBefore
        );
    }

    function testFuzz_Success_mint_LeavesTheZeroAddressUnaccrued(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint96 received
    ) public {
        // Given: A pool at a fuzzed price, and a seeded vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A reward moving the accumulator net of the fee, below what saturates it.
        uint256 supply = almCore.totalSupply();
        uint256 bps = almCore.protocolEmissionFeeBps_();
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            supply / 1e18 + 1, ConfigLib.BPS_DENOMINATOR, ConfigLib.BPS_DENOMINATOR - bps
        );
        uint256 balance = bound(
            received,
            floor,
            FixedPointMathLib.min(type(uint96).max, FixedPointMathLib.fullMulDiv(supply, type(uint128).max, 1e18))
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), balance);
        uint256 lastRewardBalance = almCore.getLastRewardBalance();
        uint256 net = balance - lastRewardBalance - (balance - lastRewardBalance) * bps / ConfigLib.BPS_DENOMINATOR;
        uint256 raised = almCore.rewardPerShare_() + FixedPointMathLib.fullMulDiv(net, 1e18, supply);

        // When: Calling mint() for up to the supply, which checkpoints the reward first.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The accumulator moved, and the zero address was not accrued.
        assertEq(almCore.rewardPerShare_(), raised);
        assertEq(almCore.getRewardSnapshot(address(0)), 0);
    }

    function testFuzz_Success_mint_EntrantInWindowEarnsOnlyItsBlocks(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 joinedAfter,
        uint256 emissions,
        uint256 shares,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked emissions for a fuzzed window, a fuzzed fee.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault whose staked range opens its window now.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions the window hides, up to a fuzzed block inside it.
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        joinedAfter = bound(joinedAfter, 1, window - 1);
        accrueForBlocks(pool, gauge, joinedAfter, emissions);
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 supply = almCore.totalSupply();

        // When: A minter joins inside the window, minting up to the supply.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: The window closes after more emissions, and the minter is credited.
        accrueForBlocks(pool, gauge, window - joinedAfter, emissions);
        almCore.updateRewards(users.unprivilegedAddress);

        // Then: The minter is credited only what accrued while it held, over that supply.
        uint256 lifetime = gauge.earned(address(almCore), almCore.stakedTokenIds());
        lifetime -= lifetime * feeBps / ConfigLib.BPS_DENOMINATOR;
        assertEq(
            almCore.getPendingReward(users.unprivilegedAddress),
            FixedPointMathLib.fullMulDiv(
                shares, FixedPointMathLib.fullMulDiv(lifetime - hidden, 1e18, supply + shares), 1e18
            )
        );
    }

    function testFuzz_Success_mint_OneBlockBeforeTheCloseGainsNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked sides' emissions for a fuzzed window.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault whose staked range opens its window now.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions the window hides, up to its last block.
        accrueForBlocks(pool, gauge, window - 1, bound(emissions, 1, Constants.MAX_EMISSIONS));

        // When: A minter joins in the last block of the window, minting up to the supply.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: The window closes without more emissions, and the minter is credited.
        vm.roll(vm.getBlockNumber() + 1);
        almCore.updateRewards(users.unprivilegedAddress);

        // Then: The minter is credited nothing of what the window hid.
        assertEq(almCore.getPendingReward(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_mint_ExistingHoldersKeepTheHiddenPart(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 joinedAfter,
        uint256 emissions,
        uint256 shares,
        uint16 feeBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked emissions for a fuzzed window, a fuzzed fee.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(feeBps, 0, users.feeRecipient);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));

        // And: A seeded vault whose staked range opens its window now.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 balance = almCore.balanceOf(users.steward);

        // And: Emissions the window hides, up to a fuzzed block inside it.
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        joinedAfter = bound(joinedAfter, 1, window - 1);
        accrueForBlocks(pool, gauge, joinedAfter, emissions);
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * feeBps / ConfigLib.BPS_DENOMINATOR;
        uint256 supply = almCore.totalSupply();

        // When: A minter joins inside the window, minting up to the supply.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: The window closes after more emissions, and the seed holder is credited.
        accrueForBlocks(pool, gauge, window - joinedAfter, emissions);
        almCore.updateRewards(users.steward);

        // Then: The seed holder keeps the hidden part, the rest shared with the minter.
        uint256 lifetime = gauge.earned(address(almCore), almCore.stakedTokenIds());
        lifetime -= lifetime * feeBps / ConfigLib.BPS_DENOMINATOR;
        assertEq(
            almCore.getPendingReward(users.steward),
            FixedPointMathLib.fullMulDiv(
                balance,
                FixedPointMathLib.fullMulDiv(hidden, 1e18, supply)
                    + FixedPointMathLib.fullMulDiv(lifetime - hidden, 1e18, supply + shares),
                1e18
            )
        );
    }

    function testFuzz_Success_mint_EntrantWhileTheWindowTokenIsOutOfRangeEarnsNothingFromIt(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory narrow,
        uint256 window,
        uint256 heldFor,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding staked emissions for a fuzzed window of two blocks or more.
        window = bound(window, 3, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A wide range around the price with a staked leg.
        givenValidRangeState(range, poolState, false);
        {
            range.tickLower = int24(
                bound(
                    range.tickLower / poolState.tickSpacing,
                    -(bandTick(poolState.tickSpacing) / poolState.tickSpacing) + 1,
                    (poolState.tickCurrent - poolState.tickSpacing) / poolState.tickSpacing
                )
            ) * poolState.tickSpacing;
            range.tickUpper = int24(
                bound(
                    range.tickUpper / poolState.tickSpacing,
                    (poolState.tickCurrent + 3 * poolState.tickSpacing) / poolState.tickSpacing,
                    (bandTick(poolState.tickSpacing) / poolState.tickSpacing) - 1
                )
            ) * poolState.tickSpacing;
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A seeded vault with the wide range staked outside its window.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256[] memory wideTokenId = new uint256[](1);
        wideTokenId[0] = range.stakedTokenId;
        closePenaltyWindow(gauge);

        // And: A narrow range up to a spacing above spot, staked now, by the wide one.
        int24 narrowUpper =
            (poolState.tickCurrent + poolState.tickSpacing) / poolState.tickSpacing * poolState.tickSpacing;
        givenValidRangeState(narrow, poolState, false);
        {
            narrow.tickUpper = narrowUpper;
            narrow.tickLower = int24(
                bound(
                    narrow.tickLower / poolState.tickSpacing,
                    -bandTick(poolState.tickSpacing) / poolState.tickSpacing + 1,
                    narrowUpper / poolState.tickSpacing - 1
                )
            ) * poolState.tickSpacing;
            uint128 free = liquidityCeiling(narrow.tickLower, narrow.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            narrow.liquidity = uint128(bound(narrow.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
            narrow.liquidityStaked = uint128(bound(narrow.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }
        setRangeState(narrow);
        uint256 stakedAt = vm.getBlockNumber();
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        accrueForBlocks(pool, gauge, 1, emissions);

        // And: A trade out of the narrow range, then a minter of up to the supply.
        parkAtTick(pool, accountA, narrowUpper + poolState.tickSpacing);
        uint256 liveBefore = gauge.earned(address(almCore), wideTokenId);
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // When: Emissions accrue for blocks inside the window, then the minter exits.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 2), emissions);
        uint256 liveShare = FixedPointMathLib.fullMulDiv(
            gauge.earned(address(almCore), wideTokenId) - liveBefore, shares, almCore.totalSupply()
        );
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // And: The price returns into the narrow range, the window closes after accrual.
        parkAtTick(pool, accountA, poolState.tickCurrent);
        accrueForBlocks(pool, gauge, stakedAt + window - vm.getBlockNumber(), emissions);
        almCore.checkpoint_();

        // Then: The minter holds at most its share of the wide range's accrual it held.
        assertLe(almCore.getPendingReward(users.unprivilegedAddress), liveShare);
    }

    function testFuzz_Success_mint_WorkedExampleG2(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A ten block window hiding the whole accrual, and no protocol share.
        setPenaltyConfig(10, MAX_PIPS);

        // And: A range around the price, room for two of it and the supply to triple.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 24, free / 12));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, free / 24, free / 12));

        // And: A seeded vault, supply up to 1e18, Alice holding all but the dead shares.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        coreState.supply = bound(coreState.supply, 2 * almCore.DEAD_SHARES_() + 1, 1e18);
        setCoreState(coreState);
        uint256 alice = almCore.balanceOf(users.steward);
        uint256 dead = almCore.DEAD_SHARES_();

        // And: Range B staked outside its window, and its twin range A staked at block 0.
        setRangeState(range);
        closePenaltyWindow(gauge);
        RangeState memory twin = RangeState({
            index: 0,
            tickLower: range.tickLower,
            tickUpper: range.tickUpper,
            liquidity: range.liquidity,
            liquidityStaked: range.liquidityStaked,
            unstakedTokenId: 0,
            stakedTokenId: 0
        });
        setRangeState(twin);
        uint256[] memory tokenIds = almCore.stakedTokenIds();
        uint256[4] memory accrued;
        accrued[0] = earnedWithoutPenalty(gauge, address(almCore), tokenIds);

        // And: Bob and Carol funded to mint Alice's balance each.
        token0.mint(accountB, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(accountB, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(accountC, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(accountC, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(accountB);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(accountC);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        vm.stopPrank();

        // When: Blocks 0 to 9 accrue, Bob minting Alice's balance at block 5, Carol at 9.
        emissions = bound(emissions, 1e6, Constants.MAX_EMISSIONS / 10);
        for (uint256 i; i < 5; ++i) {
            accrueForBlocks(pool, gauge, 1, emissions);
        }
        accrued[1] = earnedWithoutPenalty(gauge, address(almCore), tokenIds);
        vm.prank(accountB);
        almCore.mint(alice, accountB);
        for (uint256 i; i < 4; ++i) {
            accrueForBlocks(pool, gauge, 1, emissions);
        }
        accrued[2] = earnedWithoutPenalty(gauge, address(almCore), tokenIds);
        vm.prank(accountC);
        almCore.mint(alice, accountC);
        accrueForBlocks(pool, gauge, 1, emissions);
        accrued[3] = gauge.earned(address(almCore), tokenIds);

        // And: Carol exits at block 10 as the window closes, Alice and Bob credited.
        vm.prank(accountC);
        almCore.burn(alice, accountC, accountC);
        almCore.updateRewards(users.steward);
        almCore.updateRewards(accountB);

        // Then: Each holder is credited each held block's accrual over its supply.
        assertEq(accrued[0], 0);
        uint256 rps1 = (accrued[1] - accrued[0]) * 1e18 / (alice + dead);
        uint256 rps2 = (accrued[2] - accrued[1]) * 1e18 / (2 * alice + dead);
        uint256 rps3 = (accrued[3] - accrued[2]) * 1e18 / (3 * alice + dead);
        assertEq(almCore.getPendingReward(users.steward), alice * (rps1 + rps2 + rps3) / 1e18);
        assertEq(almCore.getPendingReward(accountB), alice * (rps2 + rps3) / 1e18);
        assertEq(almCore.getPendingReward(accountC), alice * rps3 / 1e18);
    }

    function testFuzz_Success_mint_CountsTheGaugeEarnedOnAnyChainStatus(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 blocks,
        uint256 emissions,
        uint256 status
    ) public {
        // Given: A pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around the price with a staked leg.
        givenValidRangeState(range, poolState, true);
        {
            uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
            range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        }

        // And: A seeded vault with the staked sibling outside its penalty window.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: Emissions on the staked side, on any chain status.
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));
        setAnyStatus(status);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 net = earned - earned * almCore.protocolEmissionFeeBps_() / ConfigLib.BPS_DENOMINATOR;
        highWater += net;
        uint256 delta = FixedPointMathLib.fullMulDiv(net, 1e18, almCore.totalSupply());

        // When: Calling mint() for up to the supply, a doubling the tick room holds.
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(bound(shares, 1, coreState.supply), users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The gauge earned is spread over the supply on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);
        assertEq(almCore.getRewardHighWater(), highWater);

        // And: The receiver starts at that accumulator, the reward still at the gauge.
        assertEq(almCore.getRewardSnapshot(users.unprivilegedAddress), rewardPerShare + delta);
        assertEq(gauge.earned(address(almCore), almCore.stakedTokenIds()), earned);
    }
}

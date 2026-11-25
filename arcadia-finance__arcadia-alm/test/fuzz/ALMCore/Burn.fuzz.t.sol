/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { IMetadexCLGauge } from "../../../src/interfaces/IMetadexCLGauge.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { VmSafe } from "@forge-std/Vm.sol";

/**
 * @notice Fuzz tests for the function "burn" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unsafe-typecast, unused-return)
contract Burn_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_burn_InsufficientAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 allowance,
        address caller
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: A caller other than the holder with too small an allowance.
        vm.assume(caller != users.unprivilegedAddress && caller != address(0));
        allowance = bound(allowance, 0, shares - 1);
        vm.prank(users.unprivilegedAddress);
        almCore.approve(caller, allowance);

        // When: Calling burn() for the holder.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        almCore.burn(shares, caller, users.unprivilegedAddress);
    }

    function testFuzz_Revert_burn_NotInitialized(PoolState memory poolState, address holder, uint256 shares) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A core that was never seeded.

        // When: A holder withdraws its own shares.
        // Then: It reverts.
        vm.prank(holder);
        vm.expectRevert(ALMCore.NotInitialized.selector);
        almCore.burn(shares, holder, holder);
    }

    function testFuzz_Revert_burn_InsufficientBalance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 balance,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        balance = bound(balance, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(balance, users.unprivilegedAddress);
        vm.stopPrank();

        // And: A holder withdrawing more shares than it holds.
        shares = bound(shares, balance + 1, type(uint256).max);

        // When: The holder withdraws.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ERC20.InsufficientBalance.selector);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);
    }

    function testFuzz_Revert_burn_RevertingGaugeOnTheStakedSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bytes memory reason
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder's exit reaches the staked side.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();

        // And: A gauge whose withdraw reverts.
        vm.mockCallRevert(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.withdraw.selector), reason);

        // When: The seed holder withdraws more than the unstaked side covers.
        // Then: It reverts with the gauge's reason.
        vm.prank(users.steward);
        vm.expectRevert(reason);
        almCore.burn(shares, users.steward, users.steward);
    }

    function testFuzz_Success_burn_DeviatingPrice(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 amountIn,
        uint256 maxSpotFromTwap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A fee-earning trade.
        amountIn = feeEarningTrade(pool, range.liquidity, amountIn, true);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: The trade pushed spot away from the TWAP.
        swapInPool(pool, users.liquidityProvider, address(token0), address(token1), amountIn);

        // And: A band between spot and the TWAP narrower than spot's distance from it.
        setSpotFromTwap(outsideBand(maxSpotFromTwap, spotFromTwap(false)));

        // When: The holder withdraws.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: The exit goes through and the shares are burned.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_burn_SpendsAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        address caller
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: A caller without code, other than the holder, that the holder approved.
        vm.assume(caller != users.unprivilegedAddress && caller != address(0));
        vm.assume(caller.code.length == 0);
        vm.prank(users.unprivilegedAddress);
        almCore.approve(caller, shares);
        uint256 balance0Before = token0.balanceOf(caller);
        uint256 balance1Before = token1.balanceOf(caller);

        // When: The caller withdraws the holder's shares to itself.
        vm.prank(caller);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, caller, users.unprivilegedAddress);

        // Then: The allowance is spent and the caller received the tokens.
        assertEq(almCore.allowance(users.unprivilegedAddress, caller), 0);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(token0.balanceOf(caller) - balance0Before, amount0);
        assertEq(token1.balanceOf(caller) - balance1Before, amount1);
    }

    function testFuzz_Success_burn_OwnOperatorSpendsNoAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        address holder = users.unprivilegedAddress;
        shares = bound(shares, 1, coreState.supply);
        token0.mint(holder, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(holder, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(holder);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, holder);
        vm.stopPrank();
        uint256 balance0Before = token0.balanceOf(holder);
        uint256 balance1Before = token1.balanceOf(holder);

        // And: The holder is its own operator, with no allowance to itself.
        vm.prank(asyncVault0);
        almCore.setOperator(holder, holder, true);

        // When: The holder burns its shares to itself.
        vm.prank(holder);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, holder, holder);

        // Then: The shares are burned and the holder received the tokens.
        assertEq(almCore.balanceOf(holder), 0);
        assertEq(token0.balanceOf(holder) - balance0Before, amount0);
        assertEq(token1.balanceOf(holder) - balance1Before, amount1);
    }

    function testFuzz_Success_burn_AmountsEqualTheProRataClaim(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: Its claim on the range's unstaked side and the buffer, rounded down.
        uint256 supply = almCore.totalSupply();
        uint256 expected0;
        uint256 expected1;
        Range memory staged = almCore.getRange(range.index);
        uint128 owed = uint128(
            (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity).fullMulDiv(shares, supply)
        );
        (expected0, expected1) = amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, owed);
        expected0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
        expected1 += almCore.bufferAmount1().fullMulDiv(shares, supply);

        // When: The holder withdraws.
        vm.prank(users.unprivilegedAddress);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: The holder received its claim and the shares are burned.
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(almCore.totalSupply(), supply - shares);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1());
    }

    function testFuzz_Success_burn_PaysTheProRataOfTheDonatedLiquidity(
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

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: A third party then added liquidity to the range's position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));
        uint128 liquidityBefore = positionLiquidity(range.unstakedTokenId);

        // And: The holder's claim on the whole position and the buffer, rounded down.
        uint256 supply = almCore.totalSupply();
        uint128 owed = uint128(uint256(liquidityBefore).fullMulDiv(shares, supply));
        (uint256 expected0, uint256 expected1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, owed);
        expected0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
        expected1 += almCore.bufferAmount1().fullMulDiv(shares, supply);

        // When: The holder burns.
        vm.prank(users.unprivilegedAddress);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: The holder got its claim, donation included, the position shrank by it.
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(positionLiquidity(range.unstakedTokenId), liquidityBefore - owed);
    }

    function testFuzz_Success_burn_ScalesEveryRangeByTheSameFraction(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding two ranges.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        givenValidRangeState(second, poolState, false);
        setRangeState(second);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: Each range's liquidity pro rata to the shares, rounded down.
        Range memory rangeBefore = almCore.getRange(range.index);
        Range memory secondBefore = almCore.getRange(second.index);
        uint128 unstakedBefore = positionLiquidity(rangeBefore.unstakedTokenId);
        uint128 secondUnstakedBefore = positionLiquidity(secondBefore.unstakedTokenId);
        uint256 supply = almCore.totalSupply();
        uint256 owed = (uint256(unstakedBefore) + rangeBefore.stakedLiquidity).fullMulDiv(shares, supply);
        uint256 owedSecond = (uint256(secondUnstakedBefore) + secondBefore.stakedLiquidity).fullMulDiv(shares, supply);

        // When: The holder withdraws.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: Both ranges shed exactly their pro-rata share.
        assertEq(unstakedBefore - positionLiquidity(rangeBefore.unstakedTokenId), owed);
        assertEq(secondUnstakedBefore - positionLiquidity(secondBefore.unstakedTokenId), owedSecond);
    }

    function testFuzz_Success_burn_PaysItsShareOfAllFees(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 dustLiquidity,
        uint256 amountIn,
        uint16 feeBps,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An unstaked range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A burn of the seed holder's shares.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));

        // And: A dust range at the same ticks the burn takes no liquidity from.
        RangeState memory dust;
        (dust.tickLower, dust.tickUpper) = (range.tickLower, range.tickUpper);
        dust.liquidity = uint128(
            bound(
                dustLiquidity,
                1,
                FixedPointMathLib.min(
                    (coreState.supply - 1) / shares, liquidityCeiling(dust.tickLower, dust.tickUpper, 1) / 4
                )
            )
        );
        setRangeState(dust);

        // And: Swap fees on both ranges, under a protocol share.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token0),
            address(token1),
            feeEarningTrade(pool, range.liquidity, amountIn, true)
        );

        // And: Both ranges' principal, the buffer and their fees, pro rata, floored.
        (uint256 expected0, uint256 expected1) = amountsRoundedDown(
            sqrtPriceX96(pool),
            range.tickLower,
            range.tickUpper,
            uint128(uint256(range.liquidity).fullMulDiv(shares, almCore.totalSupply()))
        );
        (uint256 dust0, uint256 dust1) = amountsRoundedDown(
            sqrtPriceX96(pool),
            dust.tickLower,
            dust.tickUpper,
            uint128(uint256(dust.liquidity).fullMulDiv(shares, almCore.totalSupply()))
        );
        (expected0, expected1) = (expected0 + dust0, expected1 + dust1);
        (uint256 fees0, uint256 fees1) = positionFees(pool, range.unstakedTokenId);
        (uint256 dustFees0, uint256 dustFees1) = positionFees(pool, dust.unstakedTokenId);
        (fees0, fees1) = (fees0 + dustFees0, fees1 + dustFees1);
        expected0 += (almCore.bufferAmount0() + fees0 - fees0 * feeBps / almCore.BPS_DENOMINATOR_())
        .fullMulDiv(shares, almCore.totalSupply());
        expected1 += (almCore.bufferAmount1() + fees1 - fees1 * feeBps / almCore.BPS_DENOMINATOR_())
        .fullMulDiv(shares, almCore.totalSupply());

        // When: The seed holder burns the shares.
        vm.prank(users.steward);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.steward, users.steward);

        // Then: It pays the principal, its buffer share and every range's net fees.
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
    }

    function testFuzz_Success_burn_PaysItsShareOfAllFees_Token1Fees(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint128 dustLiquidity,
        uint256 amountIn,
        uint16 feeBps,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An unstaked range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true, false);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A burn of the seed holder's shares.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));

        // And: A dust range at the same ticks the burn takes no liquidity from.
        RangeState memory dust;
        (dust.tickLower, dust.tickUpper) = (range.tickLower, range.tickUpper);
        dust.liquidity = uint128(
            bound(
                dustLiquidity,
                1,
                FixedPointMathLib.min(
                    (coreState.supply - 1) / shares, liquidityCeiling(dust.tickLower, dust.tickUpper, 1) / 4
                )
            )
        );
        setRangeState(dust);

        // And: Token1 swap fees on both ranges, under a protocol share.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        swapInPool(
            pool,
            users.liquidityProvider,
            address(token1),
            address(token0),
            feeEarningTrade(pool, range.liquidity, amountIn, false)
        );

        // And: Both ranges' principal, the buffer and their fees, pro rata, floored.
        (uint256 expected0, uint256 expected1) = amountsRoundedDown(
            sqrtPriceX96(pool),
            range.tickLower,
            range.tickUpper,
            uint128(uint256(range.liquidity).fullMulDiv(shares, almCore.totalSupply()))
        );
        (uint256 dust0, uint256 dust1) = amountsRoundedDown(
            sqrtPriceX96(pool),
            dust.tickLower,
            dust.tickUpper,
            uint128(uint256(dust.liquidity).fullMulDiv(shares, almCore.totalSupply()))
        );
        (expected0, expected1) = (expected0 + dust0, expected1 + dust1);
        (uint256 fees0, uint256 fees1) = positionFees(pool, range.unstakedTokenId);
        (uint256 dustFees0, uint256 dustFees1) = positionFees(pool, dust.unstakedTokenId);
        (fees0, fees1) = (fees0 + dustFees0, fees1 + dustFees1);
        expected0 += (almCore.bufferAmount0() + fees0 - fees0 * feeBps / almCore.BPS_DENOMINATOR_())
        .fullMulDiv(shares, almCore.totalSupply());
        expected1 += (almCore.bufferAmount1() + fees1 - fees1 * feeBps / almCore.BPS_DENOMINATOR_())
        .fullMulDiv(shares, almCore.totalSupply());

        // When: The seed holder burns the shares.
        vm.prank(users.steward);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.steward, users.steward);

        // Then: It pays the principal, its buffer share and every range's net fees.
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
    }

    function testFuzz_Success_burn_SiblingCoversSoNoGaugeCall(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with a staked leg no larger than its unstaked leg.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, range.liquidity));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The staked sibling's liquidity before the withdraw.
        uint128 stakedBefore = almCore.getRange(range.index).stakedLiquidity;
        shares = bound(shares, 1, FixedPointMathLib.min(almCore.balanceOf(users.steward), coreState.supply / 2));

        // When: The seed holder withdraws up to half the supply, the sibling covering it.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.withdraw.selector), 0);
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.deposit.selector), 0);
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // Then: The staked sibling kept its liquidity, in the core and in its position.
        assertEq(almCore.getRange(range.index).stakedLiquidity, stakedBefore);
        assertEq(positionLiquidity(almCore.getRange(range.index).stakedTokenId), stakedBefore);
    }

    function testFuzz_Success_burn_SiblingShortUnstakesAndRestakes(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder's exit reaches the staked side.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: The seed holder's claim, the unstaked side first, and the buffer, floored.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        uint128 stakedBefore = almCore.getRange(range.index).stakedLiquidity;
        uint256 owed = (uint256(range.liquidity) + range.liquidityStaked).fullMulDiv(shares, coreState.supply);
        uint256 claim0;
        uint256 claim1;
        uint160 sqrtPrice = sqrtPriceX96(pool);
        (claim0, claim1) = amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, range.liquidity);
        (uint256 staked0, uint256 staked1) =
            amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, uint128(owed - range.liquidity));
        claim0 += staked0 + almCore.bufferAmount0().fullMulDiv(shares, coreState.supply);
        claim1 += staked1 + almCore.bufferAmount1().fullMulDiv(shares, coreState.supply);

        // When: The seed holder withdraws more than the unstaked sibling can cover.
        vm.prank(users.steward);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.steward, users.steward);

        // Then: The staked sibling paid the rest, kept its token id, was restaked now.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, range.stakedTokenId);
        assertEq(staged.stakedBlock, vm.getBlockNumber());
        assertEq(staged.stakedLiquidity, stakedBefore - (owed - range.liquidity));
        assertEq(staged.stakedLiquidity, positionLiquidity(range.stakedTokenId));
        assertTrue(gauge.stakedContains(address(almCore), range.stakedTokenId));

        // And: The holder received its claim, nothing more out of the buffer.
        assertEq(amount0, claim0);
        assertEq(amount1, claim1);
        assertEq(token0.balanceOf(address(almCore)), almCore.bufferAmount0() + almCore.getProtocolFees0());
        assertEq(token1.balanceOf(address(almCore)), almCore.bufferAmount1() + almCore.getProtocolFees1());
    }

    function testFuzz_Success_burn_EmergencyUnstakeReopensTheExitPastARevertingGauge(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bytes memory reason
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder's exit reaches the staked side.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: A gauge whose withdraw reverts, the staked side emergency withdrawn.
        vm.mockCallRevert(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.withdraw.selector), reason);
        clGaugeFactory.setEmergencyWithdrawEnabled(true);
        runPlan(Plan.init().emergencyUnstake(range.index, range.stakedTokenId));

        // And: The seed holder's claim on the unstaked side and the buffer, floored.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        uint256 supply = almCore.totalSupply();
        uint256 owed = uint256(positionLiquidity(range.unstakedTokenId)).fullMulDiv(shares, supply);
        (uint256 claim0, uint256 claim1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, uint128(owed));
        claim0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
        claim1 += almCore.bufferAmount1().fullMulDiv(shares, supply);

        // When: The seed holder withdraws all its shares.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.withdraw.selector), 0);
        vm.prank(users.steward);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.steward, users.steward);

        // Then: It paid its claim without calling the gauge.
        assertEq(amount0, claim0);
        assertEq(amount1, claim1);
        assertEq(almCore.getRange(range.index).stakedTokenId, 0);
    }

    function testFuzz_Success_burn_ReadsThePenaltyConfigOnce(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder's exit reaches the staked sides.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A second mostly staked range, both outside their penalty window.
        givenValidRangeState(second, poolState, false);
        second.liquidityStaked = uint128(bound(second.liquidityStaked, second.liquidity, 2 * second.liquidity));
        setRangeState(second);
        closePenaltyWindow(gauge);
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();

        // And: A checkpoint after the windows closed, which clears the window end.
        almCore.checkpoint_();

        // When: The seed holder withdraws more than either unstaked sibling can cover.
        vm.startStateDiffRecording();
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);
        VmSafe.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();

        // Then: Both staked sides paid what their unstaked side did not cover.
        assertEq(
            almCore.getRange(range.index).stakedLiquidity,
            range.liquidity + range.liquidityStaked
                - (uint256(range.liquidity) + range.liquidityStaked).fullMulDiv(shares, coreState.supply)
        );
        assertEq(
            almCore.getRange(second.index).stakedLiquidity,
            second.liquidity + second.liquidityStaked
                - (uint256(second.liquidity) + second.liquidityStaked).fullMulDiv(shares, coreState.supply)
        );

        // And: The core read the gauge's penalty configuration once for both.
        uint256 reads;
        for (uint256 i; i < accesses.length; ++i) {
            if (
                accesses[i].accessor == address(almCore) && accesses[i].account == address(clGaugeFactory)
                    && accesses[i].kind == VmSafe.AccountAccessKind.StaticCall
            ) ++reads;
        }
        assertEq(reads, 1);
    }

    function testFuzz_Success_burn_InsideThePenaltyWindowForfeitsOnlyTheEmissions(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 emissions,
        uint256 window
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A fuzzed penalty window the gauge factory holds open.
        window = bound(window, 1, type(uint40).max);
        setMinStakeBlocks(gauge, window);

        // And: A mostly staked range around the price.
        givenValidRangeState(range, poolState, true);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A vault whose holder's exit reaches the staked side, inside the window.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: The staked sibling accrued unclaimed emissions up to the ceiling.
        addEmissionsToGaugeCL(pool, gauge, bound(emissions, 2, Constants.MAX_EMISSIONS));
        uint256 snapshot = vm.snapshotState();
        vm.roll(vm.getBlockNumber() + window);
        uint256 baseReward = gauge.earned(address(almCore));
        vm.revertToState(snapshot);
        assertGt(baseReward, 0);

        // And: The holder's claim, the unstaked side first, and the buffer, rounded down.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        uint256 expected0;
        uint256 expected1;
        uint256 owed = (uint256(range.liquidity) + range.liquidityStaked).fullMulDiv(shares, coreState.supply);
        uint128 fromUnstaked = uint128(FixedPointMathLib.min(owed, range.liquidity));
        uint160 sqrtPrice = sqrtPriceX96(pool);
        (expected0, expected1) = amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, fromUnstaked);
        (uint256 staked0, uint256 staked1) =
            amountsRoundedDown(sqrtPrice, range.tickLower, range.tickUpper, uint128(owed - fromUnstaked));
        expected0 += staked0 + almCore.bufferAmount0().fullMulDiv(shares, coreState.supply);
        expected1 += staked1 + almCore.bufferAmount1().fullMulDiv(shares, coreState.supply);

        // When: The holder withdraws inside the window.
        vm.prank(users.steward);
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.steward, users.steward);

        // Then: The liquidity released is the pro-rata claim, and the emissions are lost.
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), 0);
        assertEq(almCore.getClaimedCumulative(), 0);
    }

    function testFuzz_Success_burn_DrainedStakedSiblingIsBurned(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 tokenId = almCore.getRange(range.index).stakedTokenId;
        closePenaltyWindow(gauge);

        // And: The seed holder owns the whole supply, its claim every range in full.
        almCore.burnShares(address(1), almCore.DEAD_SHARES_());
        uint256 shares = almCore.totalSupply();
        uint256 positionsBefore = POSITION_MANAGER.totalSupply();

        // When: The seed holder withdraws everything.
        vm.expectCall(address(gauge), abi.encodeWithSelector(IMetadexCLGauge.deposit.selector), 0);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Unstaked(range.index, tokenId);
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // Then: The drained sibling was burned instead of restaked.
        Range memory staged = almCore.getRange(range.index);
        assertEq(staged.stakedTokenId, 0);
        assertEq(staged.stakedLiquidity, 0);
        assertFalse(gauge.stakedContains(address(almCore), range.stakedTokenId));
        assertEq(POSITION_MANAGER.totalSupply(), positionsBefore - 1);
    }

    function testFuzz_Success_burn_RoundingNeverFavoursTheWithdrawer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        (uint256 paid0, uint256 paid1) = almCore.mint(shares, users.unprivilegedAddress);

        // When: The holder withdraws the shares it just minted at the same price.
        (uint256 amount0, uint256 amount1) = almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: The round trip never returns more than it cost.
        assertLe(amount0, paid0);
        assertLe(amount1, paid1);
    }

    function testFuzz_Success_burn_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: The vault is paused.
        vm.prank(factory);
        almCore.pause();

        // When: The holder withdraws.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: The shares are burned.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_burn_ManipulatedPriceLeavesNoProfit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: An actor funded for a tick spacing move.
        int24 target =
            zeroForOne ? poolState.tickCurrent - poolState.tickSpacing : poolState.tickCurrent + poolState.tickSpacing;
        fundActorForTick(pool, users.unprivilegedAddress, target);

        // And: The actor's value at spot with its claim, and the vault's value per share.
        uint160 sqrtPriceBefore = sqrtPriceX96(pool);
        uint256 perShareBefore;
        uint256 valueBefore;
        {
            uint256 supply = almCore.totalSupply();
            Range memory stagedBefore = almCore.getRange(range.index);
            (uint256 held0, uint256 held1) = amountsRoundedDown(
                sqrtPriceBefore,
                stagedBefore.tickLower,
                stagedBefore.tickUpper,
                positionLiquidity(stagedBefore.unstakedTokenId) + stagedBefore.stakedLiquidity
            );
            held0 += almCore.bufferAmount0();
            held1 += almCore.bufferAmount1();
            perShareBefore = (held1 + token0ToToken1(sqrtPriceBefore, held0)).fullMulDiv(1e18, supply);
            uint128 owed = uint128(
                (uint256(positionLiquidity(stagedBefore.unstakedTokenId)) + stagedBefore.stakedLiquidity)
                .fullMulDiv(shares, supply)
            );
            (uint256 claim0, uint256 claim1) =
                amountsRoundedDown(sqrtPriceBefore, stagedBefore.tickLower, stagedBefore.tickUpper, owed);
            claim0 += almCore.bufferAmount0().fullMulDiv(shares, supply) + token0.balanceOf(users.unprivilegedAddress);
            claim1 += almCore.bufferAmount1().fullMulDiv(shares, supply) + token1.balanceOf(users.unprivilegedAddress);
            valueBefore = claim1 + token0ToToken1(sqrtPriceBefore, claim0);
        }

        // And: The actor pushed the pool price a tick spacing at its own cost.
        pushPriceToTick(pool, users.unprivilegedAddress, target);

        // When: Withdrawing at the manipulated price and restoring the price exactly.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);
        uint256 restoreFunding = fundActorForPrice(pool, users.unprivilegedAddress, sqrtPriceBefore);
        if (sqrtPriceBefore < sqrtPriceX96(pool)) restoreFunding = token0ToToken1(sqrtPriceBefore, restoreFunding);
        restorePrice(pool, users.unprivilegedAddress, zeroForOne, sqrtPriceBefore);
        valueBefore += restoreFunding;

        // Then: The round trip left the actor no better off at the restored price.
        assertEq(sqrtPriceX96(pool), sqrtPriceBefore);
        assertLe(
            token1.balanceOf(users.unprivilegedAddress)
                + token0ToToken1(sqrtPriceBefore, token0.balanceOf(users.unprivilegedAddress)),
            valueBefore
        );

        // And: The stayer's value per share fell by a floored wei a token at most.
        Range memory staged = almCore.getRange(range.index);
        (uint256 after0, uint256 after1) = amountsRoundedDown(
            sqrtPriceBefore,
            staged.tickLower,
            staged.tickUpper,
            positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
        );
        (uint256 fees0, uint256 fees1) = positionFees(pool, staged.unstakedTokenId);
        perShareBefore = perShareBefore.zeroFloorSub(
            (FixedPointMathLib.fullMulDivUp(1, uint256(sqrtPriceBefore) * sqrtPriceBefore, 1 << 192) + 2)
            .fullMulDivUp(1e18, almCore.totalSupply())
        );
        after0 += almCore.bufferAmount0() + fees0;
        after1 += almCore.bufferAmount1() + fees1;
        assertGe(
            (after1 + token0ToToken1(sqrtPriceBefore, after0)).fullMulDiv(1e18, almCore.totalSupply()), perShareBefore
        );
    }

    function testFuzz_Success_burn_FloorsTheProtocolFeeOnTheSum(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        uint16 feeBps,
        uint256 amountIn
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range around the price, a real share of the room.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder's exit reaches the staked sides.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A second mostly staked range around the price.
        givenValidRangeState(second, poolState, true);
        free = liquidityCeiling(second.tickLower, second.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        second.liquidity = uint128(bound(second.liquidity, free / 8, free / 4));
        second.liquidityStaked = uint128(bound(second.liquidityStaked, second.liquidity, 2 * second.liquidity));
        setRangeState(second);
        closePenaltyWindow(gauge);

        // And: A protocol share of every collection, and fees left on both ranges.
        feeBps = uint16(bound(feeBps, 1, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        amountIn =
            feeEarningTrade(pool, uint128(FixedPointMathLib.min(range.liquidity, second.liquidity)), amountIn, true);
        swapInPool(pool, users.liquidityProvider, address(token0), address(token1), amountIn);
        swapInPool(pool, users.liquidityProvider, address(token1), address(token0), amountIn);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: Each range's fees from fee growth.
        (uint256 first0, uint256 first1) = positionFees(pool, range.unstakedTokenId);
        (uint256 second0, uint256 second1) = positionFees(pool, second.unstakedTokenId);

        // When: The seed holder withdraws more than the unstaked siblings can cover.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // Then: Both staked siblings paid what their unstaked side did not cover.
        assertEq(
            almCore.getRange(range.index).stakedLiquidity,
            range.liquidity + range.liquidityStaked
                - (uint256(range.liquidity) + range.liquidityStaked).fullMulDiv(shares, coreState.supply)
        );
        assertEq(
            almCore.getRange(second.index).stakedLiquidity,
            second.liquidity + second.liquidityStaked
                - (uint256(second.liquidity) + second.liquidityStaked).fullMulDiv(shares, coreState.supply)
        );

        // And: The protocol fee is floored once on the sum of both ranges' fees.
        assertGt(first0 + first1, 0);
        assertGt(second0 + second1, 0);
        assertEq(almCore.getProtocolFees0(), (first0 + second0) * feeBps / almCore.BPS_DENOMINATOR_());
        assertEq(almCore.getProtocolFees1(), (first1 + second1) * feeBps / almCore.BPS_DENOMINATOR_());
    }

    function testFuzz_Success_burn_EmitsFeesCollected(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        RangeState memory second,
        uint256 amountIn,
        uint16 feeBps,
        uint256 shares,
        bool zeroForOne
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: An unstaked range around the price, a spacing ahead of a trade either way.
        givenValidRangeState(range, poolState, true, false);
        givenRangeRoom(range, poolState, zeroForOne);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, free / 8, free / 4));

        // And: A seeded vault whose seed holder holds shares.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A second unstaked range around the price, the same spacing ahead.
        givenValidRangeState(second, poolState, true, false);
        givenRangeRoom(second, poolState, zeroForOne);
        free = liquidityCeiling(second.tickLower, second.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        second.liquidity = uint128(bound(second.liquidity, free / 8, free / 4));
        setRangeState(second);

        // And: A protocol share, and a trade either way that left fees on both ranges.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);
        amountIn = feeEarningTrade(
            pool, uint128(FixedPointMathLib.min(range.liquidity, second.liquidity)), amountIn, zeroForOne
        );
        swapInPool(
            pool,
            users.liquidityProvider,
            zeroForOne ? address(token0) : address(token1),
            zeroForOne ? address(token1) : address(token0),
            amountIn
        );

        // And: Both ranges' fees from fee growth.
        (uint256 fees0, uint256 fees1) = positionFees(pool, range.unstakedTokenId);
        (uint256 second0, uint256 second1) = positionFees(pool, second.unstakedTokenId);
        (fees0, fees1) = (fees0 + second0, fees1 + second1);

        // When: The seed holder burns a fuzzed part of its shares.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        vm.prank(users.steward);
        vm.expectEmit(address(almCore));
        // Then: The core reports both ranges' fees, before the protocol share.
        emit IALMCoreEvents.FeesCollected(fees0, fees1);
        almCore.burn(shares, users.steward, users.steward);
    }

    function testFuzz_Success_burn_NoFeesEmitsNoFeesCollected(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault with a range no trade crossed.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: The seed holder burns a fuzzed part of its shares.
        shares = bound(shares, 1, almCore.balanceOf(users.steward));
        vm.recordLogs();
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // Then: The core reports no fees.
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            assertTrue(logs[i].topics[0] != IALMCoreEvents.FeesCollected.selector);
        }
    }

    function testFuzz_Success_burn_EmitsBurn_OneReceiver(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        address receiver
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();
        vm.assume(receiver != address(0) && receiver != address(almCore));

        // And: Its claim on the range's unstaked side and the buffer, rounded down.
        uint256 amount0;
        uint256 amount1;
        uint256 supply = almCore.totalSupply();
        Range memory staged = almCore.getRange(range.index);
        uint128 owed = uint128(
            (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity).fullMulDiv(shares, supply)
        );
        (amount0, amount1) = amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, owed);
        amount0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
        amount1 += almCore.bufferAmount1().fullMulDiv(shares, supply);

        // When: The holder withdraws both tokens to one receiver.
        vm.prank(users.unprivilegedAddress);
        vm.expectEmit(address(almCore));
        // Then: The core reports that receiver.
        emit IALMCoreEvents.Burn(
            users.unprivilegedAddress, receiver, users.unprivilegedAddress, shares, amount0, amount1
        );
        almCore.burn(shares, receiver, users.unprivilegedAddress);
    }

    function testFuzz_Success_burn_AboveTheCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: A per user cap of nothing, below the holder's balance.
        vm.prank(factory);
        almCore.setPerUserCap(0);

        // When: The holder withdraws.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: It is not checked.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_burn_LeavesTheZeroAddressUnaccrued(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint96 received
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: A holder that minted up to the supply, a doubling the tick room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: A reward moving the accumulator net of the fee, below what saturates it.
        uint256 supply = almCore.totalSupply();
        uint256 bps = almCore.protocolEmissionFeeBps_();
        uint256 floor = FixedPointMathLib.fullMulDivUp(
            supply / 1e18 + 1, almCore.BPS_DENOMINATOR_(), almCore.BPS_DENOMINATOR_() - bps
        );
        uint256 balance = bound(
            received,
            floor,
            FixedPointMathLib.min(type(uint96).max, FixedPointMathLib.fullMulDiv(supply, type(uint128).max, 1e18))
        );
        deal(almCore.REWARD_TOKEN_(), address(almCore), balance);
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 lastRewardBalance = almCore.getLastRewardBalance();
        uint256 protocolFees = almCore.getProtocolFeesReward();
        uint256 fee = (balance - lastRewardBalance) * bps / almCore.BPS_DENOMINATOR_();

        // When: The holder withdraws, which checkpoints the reward first.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: The accumulator moved, and the zero address was not accrued.
        uint256 raised = rewardPerShare + FixedPointMathLib.fullMulDiv(balance - lastRewardBalance - fee, 1e18, supply);
        assertEq(almCore.rewardPerShare_(), raised);
        assertEq(almCore.getRewardSnapshot(address(0)), 0);

        // And: The reward received is measured, and its protocol share accrued.
        assertEq(almCore.getLastRewardBalance(), balance);
        assertEq(almCore.getProtocolFeesReward(), protocolFees + fee);

        // And: The owner was credited up to the raised accumulator.
        assertEq(almCore.getRewardSnapshot(users.unprivilegedAddress), raised);
    }

    function testFuzz_Success_burn_ExiterInWindowKeepsItsBlocks(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 heldFor,
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

        // And: A holder minting up to the supply in that block, which the room holds.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        vm.stopPrank();

        // And: Emissions the window hides, up to a fuzzed block inside it.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        uint256 supply = almCore.totalSupply();

        // When: The holder exits inside the window.
        vm.prank(users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);

        // Then: It is credited its share of what the window hid while it held.
        assertEq(
            almCore.getPendingReward(users.unprivilegedAddress),
            FixedPointMathLib.fullMulDiv(
                shares,
                FixedPointMathLib.fullMulDiv(hidden - hidden * feeBps / almCore.BPS_DENOMINATOR_(), 1e18, supply),
                1e18
            )
        );
    }

    function testFuzz_Success_burn_RestakeIsProtected(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 heldFor,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding staked emissions for a fuzzed window of two blocks or more.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A mostly staked range around the price.
        givenValidRangeState(range, poolState, true);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A vault whose holder's exit reaches the staked side, past its window.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // When: The seed holder exits past the unstaked side, restaking the staked side.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);
        uint256 restakedAt = vm.getBlockNumber();
        uint256 rewardPerShare = almCore.rewardPerShare_();

        // And: The restaked side accrues inside its new window, and a checkpoint runs.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        almCore.checkpoint_();

        // Then: The staked side's window starts at the restake.
        assertEq(almCore.getRange(range.index).stakedBlock, restakedAt);

        // And: The window ends with the restake's, the hidden accrual pre-credited.
        assertEq(almCore.getWindowEnd(), FixedPointMathLib.min(restakedAt + window, type(uint48).max));
        assertEq(almCore.getPreCredited(), hidden);
        assertEq(
            almCore.rewardPerShare_(),
            rewardPerShare + FixedPointMathLib.fullMulDiv(hidden, 1e18, almCore.totalSupply())
        );
    }

    function testFuzz_Success_burn_InsideThePenaltyWindowLeavesABoundedDeficit(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 penaltyRate,
        uint256 heldFor,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding part of the staked emissions for a window a block can pass.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, bound(penaltyRate, 1, MAX_PIPS));

        // And: A mostly staked range around the price.
        givenValidRangeState(range, poolState, true);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A vault whose holder's exit reaches the staked side, inside its window.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions the window hides, up to a fuzzed block inside it.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        hidden -= hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();

        // When: The seed holder exits through the staked side.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // And: A checkpoint runs.
        almCore.checkpoint_();

        // Then: The high water tops the lifetime reward by the forfeited net hidden part.
        (,, uint256 total) = almCore.getRewardTotals();
        assertEq(almCore.getRewardHighWater() - total, hidden);
    }

    function testFuzz_Success_burn_RepeatedRestakesKeepTheDeficitAtOneBlock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 restakes,
        uint256 emissions
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked sides' emissions for a fuzzed window.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A range around the price, its unstaked side half its staked side at most.
        givenValidRangeState(range, poolState, true);
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 2 * Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, range.liquidityStaked / 2));

        // And: A seeded vault whose holder's exit reaches the staked side, staked now.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        uint256 balance = almCore.balanceOf(users.steward);

        // When: The seed holder exits in parts one block apart, through the staked side.
        restakes = bound(restakes, 2, 8);
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        uint256 hidden;
        for (uint256 i; i < restakes; ++i) {
            accrueForBlocks(pool, gauge, 1, emissions);
            hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
            vm.prank(users.steward);
            almCore.burn(i == 0 ? balance * 3 / 4 : balance / (4 * restakes), users.steward, users.steward);
        }

        // And: The last window closes and a checkpoint runs.
        closePenaltyWindow(gauge);
        almCore.checkpoint_();

        // Then: The deficit is the last block's forfeited part, plus a wei per restake.
        (,, uint256 total) = almCore.getRewardTotals();
        assertLe(
            almCore.getRewardHighWater() - total,
            hidden - hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_() + restakes
        );
    }

    function testFuzz_Success_burn_NeverRevertsOnTheWindowLogic(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 penaltyRate,
        uint256 referralShare,
        uint256 elapsedBefore,
        uint256 elapsedAfter,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge with a fuzzed window, penalty rate and referral share.
        window = bound(window, 1, type(uint40).max);
        setPenaltyConfig(window, bound(penaltyRate, 0, MAX_PIPS));
        setReferralConfig(gauge, accountC, bound(referralShare, 0, clGaugeFactory.maxShareCap()));

        // And: A mostly staked range.
        givenValidRangeState(range, poolState, false);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A seeded vault whose seed holder holds shares, staked now.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions, a checkpoint, then emissions to a block in or past the window.
        emissions = bound(emissions, 1, Constants.MAX_EMISSIONS);
        accrueForBlocks(pool, gauge, bound(elapsedBefore, 0, window), emissions);
        almCore.checkpoint_();
        accrueForBlocks(pool, gauge, bound(elapsedAfter, 0, window), emissions);

        // When: The seed holder exits a fuzzed part.
        uint256 balance = almCore.balanceOf(users.steward);
        shares = bound(shares, 1, balance);
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // Then: The exit went through.
        assertEq(almCore.balanceOf(users.steward), balance - shares);

        // And: The next checkpoint pre-credits what the gauge hides, net of the fee.
        almCore.checkpoint_();
        uint256 hidden = hiddenEmissions(gauge, address(almCore), almCore.stakedTokenIds());
        assertEq(
            almCore.getPreCredited(), hidden - hidden * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_()
        );
    }

    function testFuzz_Success_burn_MintBurnSameBlockGainsNothing(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 window,
        uint256 heldFor,
        uint256 emissions,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A gauge hiding the staked sides' emissions for a fuzzed window.
        window = bound(window, 2, type(uint40).max);
        setPenaltyConfig(window, MAX_PIPS);

        // And: A seeded vault whose staked range opens its window now.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // And: Emissions the window hides, up to a fuzzed block inside it.
        accrueForBlocks(pool, gauge, bound(heldFor, 1, window - 1), bound(emissions, 1, Constants.MAX_EMISSIONS));

        // When: An actor mints up to the supply and burns in one block, in the window.
        shares = bound(shares, 1, coreState.supply);
        token0.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        token1.mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(almCore), type(uint256).max);
        token1.approve(address(almCore), type(uint256).max);
        almCore.mint(shares, users.unprivilegedAddress);
        almCore.burn(shares, users.unprivilegedAddress, users.unprivilegedAddress);
        vm.stopPrank();

        // Then: It is credited nothing.
        assertEq(almCore.getPendingReward(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_burn_StakedExitDefersTheRewardWhileTheChainDoesNotMint(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 blocks,
        uint256 emissions,
        bool mintable,
        uint256 pick
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A mostly staked range around the price.
        givenValidRangeState(range, poolState, true);
        range.liquidityStaked = uint128(bound(range.liquidityStaked, range.liquidity, 2 * range.liquidity));

        // And: A vault whose holder's exit reaches the staked side, past its window.
        givenValidCoreState(coreState, poolState, range, 3 * almCore.DEAD_SHARES_(), 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        closePenaltyWindow(gauge);

        // And: Emissions on the staked side, and a chain status that mints or does not.
        accrueForBlocks(pool, gauge, bound(blocks, 1, type(uint32).max), bound(emissions, 2, Constants.MAX_EMISSIONS));
        if (mintable) setMintableStatus(pick);
        else setNotMintableStatus(pick);
        uint256 earned = gauge.earned(address(almCore), almCore.stakedTokenIds());
        uint256 net = earned - earned * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 delta = FixedPointMathLib.fullMulDiv(net, 1e18, coreState.supply);

        // When: The seed holder exits past the unstaked side, through the staked side.
        uint256 shares = coreState.supply - almCore.DEAD_SHARES_();
        vm.prank(users.steward);
        almCore.burn(shares, users.steward, users.steward);

        // Then: The gauge paid the staked reward to the core, or deferred it off a mint.
        assertEq(ERC20(almCore.REWARD_TOKEN_()).balanceOf(address(almCore)), mintable ? earned : 0);
        assertEq(gauge.deferredEmissions(address(almCore)), mintable ? 0 : earned);

        // And: The checkpoint counted the earned reward on either status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);
        assertEq(almCore.getRewardHighWater(), highWater + net);

        // And: The holder is credited at the balance it burned.
        assertEq(almCore.getPendingReward(users.steward), FixedPointMathLib.fullMulDiv(shares, delta, 1e18));
    }
}

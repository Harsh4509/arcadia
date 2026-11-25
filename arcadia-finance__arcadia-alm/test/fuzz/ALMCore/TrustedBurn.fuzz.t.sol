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
import { Range } from "../../../src/core/types/Range.sol";

/**
 * @notice Fuzz tests for the function "trustedBurn" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
contract TrustedBurn_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_trustedBurn_OnlyVault(
        PoolState memory poolState,
        uint256 shares,
        address owner_,
        address caller,
        address sender
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A sender that is neither synchronous vault.
        vm.assume(sender != deployer.getVaults(address(almCore)).syncVault0);
        vm.assume(sender != deployer.getVaults(address(almCore)).syncVault1);

        // When: The sender calls trustedBurn().
        // Then: It reverts.
        vm.prank(sender);
        vm.expectRevert(ALMCore.OnlyVault.selector);
        almCore.trustedBurn(shares, caller, owner_, caller);
    }

    function testFuzz_Revert_trustedBurn_InsufficientAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 allowance,
        address caller,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, its seed receiver holding aLP.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 floor = almCore.DEAD_SHARES_() + 1;
        uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
        coreState.supply = bound(
            coreState.supply,
            floor,
            FixedPointMathLib.max(FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT), floor)
        );
        setCoreState(coreState);
        setRangeState(range);
        uint256 held = almCore.balanceOf(users.steward);
        shares = bound(shares, 1, held);

        // And: A vault caller, not the holder or its operator, short of allowance.
        vm.assume(caller != users.steward && caller != address(0));
        allowance = bound(allowance, 0, shares - 1);
        vm.prank(users.steward);
        almCore.approve(caller, allowance);

        // When: A synchronous vault burns the holder's shares for that caller.
        // Then: It reverts.
        vm.prank(
            isToken0 ? deployer.getVaults(address(almCore)).syncVault0 : deployer.getVaults(address(almCore)).syncVault1
        );
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        almCore.trustedBurn(shares, caller, users.steward, caller);
    }

    function testFuzz_Success_trustedBurn_ForAnOperatorWithoutAllowance(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        address operator,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with no staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding the range, its seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 floor = almCore.DEAD_SHARES_() + 1;
        uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
        coreState.supply = bound(
            coreState.supply,
            floor,
            FixedPointMathLib.max(FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT), floor)
        );
        setCoreState(coreState);
        setRangeState(range);
        uint256 held = almCore.balanceOf(users.steward);
        shares = bound(shares, 1, held);

        // And: An operator the holder approved, with no allowance.
        vm.assume(operator != users.steward && operator != address(0));
        vm.assume(operator != address(almCore) && operator != address(pool));
        address vault = isToken0
            ? deployer.getVaults(address(almCore)).syncVault0
            : deployer.getVaults(address(almCore)).syncVault1;
        vm.prank(vault);
        almCore.setOperator(users.steward, operator, true);

        // And: The holder's pro-rata claim on the range and the buffer.
        uint256 supply = almCore.totalSupply();
        Range memory staged = almCore.getRange(range.index);
        uint128 owed = uint128(uint256(positionLiquidity(staged.unstakedTokenId)).fullMulDiv(shares, supply));
        (uint256 expected0, uint256 expected1) =
            amountsRoundedDown(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, owed);
        expected0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
        expected1 += almCore.bufferAmount1().fullMulDiv(shares, supply);

        // When: A synchronous vault burns the holder's shares for the operator.
        vm.prank(vault);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Burn(vault, operator, users.steward, shares, expected0, expected1);
        almCore.trustedBurn(shares, operator, users.steward, operator);

        // Then: The shares are burned and no allowance was used.
        assertEq(almCore.balanceOf(users.steward), held - shares);
        assertEq(almCore.allowance(users.steward, operator), 0);
        assertEq(almCore.totalSupply(), supply - shares);
    }

    function testFuzz_Success_trustedBurn_PaysTheReceiverFromTheRangeAndTheBuffer(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with no staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding the range, its seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        {
            uint256 floor = almCore.DEAD_SHARES_() + 1;
            uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
            coreState.supply = bound(
                coreState.supply,
                floor,
                FixedPointMathLib.max(FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT), floor)
            );
        }
        setCoreState(coreState);
        setRangeState(range);
        shares = bound(shares, 1, almCore.balanceOf(users.steward));

        // And: The holder's pro-rata claim on the range and the buffer.
        uint256 supply = almCore.totalSupply();
        uint256 buffer0Before = almCore.bufferAmount0();
        uint256 buffer1Before = almCore.bufferAmount1();
        uint128 unstakedBefore = positionLiquidity(almCore.getRange(range.index).unstakedTokenId);
        uint128 owed = uint128(uint256(unstakedBefore).fullMulDiv(shares, supply));
        (uint256 expected0, uint256 expected1) =
            amountsRoundedDown(sqrtPriceX96(pool), range.tickLower, range.tickUpper, owed);
        expected0 += buffer0Before.fullMulDiv(shares, supply);
        expected1 += buffer1Before.fullMulDiv(shares, supply);

        // When: A sync vault burns the holder's shares to a receiver holding no tokens.
        address vault = isToken0
            ? deployer.getVaults(address(almCore)).syncVault0
            : deployer.getVaults(address(almCore)).syncVault1;
        uint256 otherBefore = (isToken0 ? token1 : token0).balanceOf(vault);
        vm.prank(vault);
        almCore.trustedBurn(shares, accountC, users.steward, users.steward);

        // Then: The range shed the holder's share of its unstaked liquidity.
        assertEq(positionLiquidity(almCore.getRange(range.index).unstakedTokenId), unstakedBefore - owed);

        // And: The receiver got the asset, the vault the other token, partly buffered.
        assertEq((isToken0 ? token0 : token1).balanceOf(accountC), isToken0 ? expected0 : expected1);
        assertEq((isToken0 ? token1 : token0).balanceOf(accountC), 0);
        assertEq((isToken0 ? token1 : token0).balanceOf(vault) - otherBefore, isToken0 ? expected1 : expected0);
        assertEq(almCore.bufferAmount0(), buffer0Before - FixedPointMathLib.fullMulDiv(buffer0Before, shares, supply));
        assertEq(almCore.bufferAmount1(), buffer1Before - FixedPointMathLib.fullMulDiv(buffer1Before, shares, supply));
    }

    function testFuzz_Success_trustedBurn_CountsTheGaugeEarnedOnAnyChainStatus(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 earned,
        uint256 status,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range with no staked leg.
        givenValidRangeState(range, poolState, false, false);

        // And: A seeded vault holding the range, its seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        uint256 floor = almCore.DEAD_SHARES_() + 1;
        uint256 value = coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0);
        coreState.supply = bound(
            coreState.supply,
            floor,
            FixedPointMathLib.max(FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT), floor)
        );
        setCoreState(coreState);
        setRangeState(range);
        uint256 held = almCore.balanceOf(users.steward);
        shares = bound(shares, 1, held);

        // And: Emissions the gauge reports, below what saturates the reward per share.
        uint256 supply = almCore.totalSupply();
        earned = bound(
            earned,
            1,
            FixedPointMathLib.min(
                Constants.MAX_FUZZED_AMOUNT, FixedPointMathLib.fullMulDiv(supply, type(uint128).max, 1e18)
            )
        );
        mockEarned(gauge, address(almCore), earned);
        uint256 net = earned - earned * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();

        // And: Any chain status.
        setAnyStatus(status);
        uint256 rewardPerShare = almCore.rewardPerShare_();
        uint256 highWater = almCore.getRewardHighWater();
        uint256 delta = FixedPointMathLib.fullMulDiv(net, 1e18, supply);
        uint256 owedBefore = almCore.getPendingReward(users.steward)
            + held.fullMulDiv(rewardPerShare + delta - almCore.getRewardSnapshot(users.steward), 1e18);

        // When: A synchronous vault burns the holder's shares.
        vm.prank(
            isToken0 ? deployer.getVaults(address(almCore)).syncVault0 : deployer.getVaults(address(almCore)).syncVault1
        );
        almCore.trustedBurn(shares, users.steward, users.steward, users.steward);

        // Then: The gauge earned is spread over the supply on any chain status.
        assertEq(almCore.rewardPerShare_(), rewardPerShare + delta);
        assertEq(almCore.getRewardHighWater(), highWater + net);

        // And: The holder is credited at the balance it held before the burn.
        assertEq(almCore.getRewardSnapshot(users.steward), rewardPerShare + delta);
        assertEq(almCore.getPendingReward(users.steward), owedBefore);
    }
}

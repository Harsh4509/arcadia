/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMAdminExtension } from "../../../src/core/ALMAdminExtension.sol";
import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCoreEvents } from "../../../src/interfaces/IALMCoreEvents.sol";
import { RouterTrampoline } from "../../utils/fixtures/asset-managers/RouterTrampoline.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";

/**
 * @notice Fuzz tests for the function "seed" of contract "ALMCore".
 */
// forge-lint: disable-next-item(reentrancy-events, unused-return)
contract Seed_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_seed_Unauthorized(
        PoolState memory poolState,
        address caller,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured and the caller is not the factory.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        vm.assume(caller != factory);

        // When: A front-runner calls seed() before the factory.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_AlreadySeeded(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 sharesSecond
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        token0.mint(factory, Constants.SEED_AMOUNT);
        token1.mint(factory, Constants.SEED_AMOUNT);
        vm.startPrank(factory);
        token0.approve(address(almCore), Constants.SEED_AMOUNT);
        token1.approve(address(almCore), Constants.SEED_AMOUNT);
        vm.stopPrank();

        // When: The factory seeds it a second time.
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.AlreadySeeded.selector);
        almCore.seed(Constants.SEED_AMOUNT, Constants.SEED_AMOUNT, sharesSecond, users.steward);
    }

    function testFuzz_Revert_seed_InvalidRecipient(PoolState memory poolState, uint256 shares) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Seeding to the zero address.
        // Then: It reverts, rather than locking the seed's shares.
        vm.prank(factory);
        vm.expectRevert(BaseCore.InvalidRecipient.selector);
        almCore.seed(Constants.SEED_AMOUNT, Constants.SEED_AMOUNT, shares, address(0));
    }

    function testFuzz_Revert_seed_NotConfigured_TwapWindow(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A core created over a pool at a fuzzed price.
        givenValidPoolState(poolState);
        deployMetadex(false);
        deployMetadexCL();
        pool = createPool(
            address(token0),
            address(token1),
            poolState.tickSpacing,
            uint160(poolState.sqrtPrice),
            OBSERVATION_CARDINALITY
        );
        gauge = createGauge(pool, true);
        routerTrampoline = new RouterTrampoline();
        deployer = deployFactory(extensionCreationCodes(), address(routerTrampoline), users.owner, users.steward);
        factory = address(deployer);
        almCore = ALMCoreExtension(
            createInThreeTransactions(
                deployer, address(pool), extensionCreationCodes(), users.steward, users.feeRecipient
            )
        );

        // And: The range cap and both caps of aLP are set but the TWAP window is not.
        vm.startPrank(factory);
        almCore.setRangeCap(ConfigLib.MAX_RANGE_CAP);
        almCore.setTotalCap(type(uint128).max);
        almCore.setPerUserCap(type(uint128).max);
        vm.stopPrank();

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_NotConfigured_PositionCap(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The TWAP window and both caps of aLP are set but the range cap is not.
        vm.startPrank(factory);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        almCore.setTotalCap(type(uint128).max);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setRangeCap(0);
        vm.stopPrank();

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_NotConfigured_TotalCap(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The TWAP window, range cap and per user cap are set, the total cap is not.
        vm.startPrank(factory);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        almCore.setRangeCap(ConfigLib.MAX_RANGE_CAP);
        almCore.setPerUserCap(type(uint128).max);
        vm.stopPrank();

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_NotConfigured_PerUserCap(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The TWAP window and both caps are set but the per user cap is not.
        vm.startPrank(factory);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        almCore.setRangeCap(ConfigLib.MAX_RANGE_CAP);
        vm.stopPrank();
        vm.prank(factory);
        almCore.setTotalCap(type(uint128).max);

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ConfigLib.NotConfigured.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_InvalidShares(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured and the shares do not exceed the dead shares.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        shares = bound(shares, 0, almCore.DEAD_SHARES_());

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidShares.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_InvalidShares_TheDeadShares(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1
    ) public {
        // Given: A pool with depth at a fuzzed price, and a configured vault.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        uint256 deadShares = almCore.DEAD_SHARES_();

        // When: Seeding exactly the dead shares.
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidShares.selector);
        almCore.seed(amount0, amount1, deadShares, users.steward);
    }

    function testFuzz_Revert_seed_TotalCapExceeded(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        uint256 cap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured with a total cap below the seed.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        shares = bound(shares, almCore.DEAD_SHARES_() + 2, Constants.MAX_FUZZED_AMOUNT);
        cap = bound(cap, almCore.DEAD_SHARES_() + 1, shares - 1);
        vm.prank(factory);
        almCore.lowerTotalCap(cap);

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Revert_seed_PerUserCapExceeded(PoolState memory poolState, uint256 shares) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A per user cap one share short of the receiver's part of the seed.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        shares = bound(shares, almCore.DEAD_SHARES_() + 2, Constants.MAX_FUZZED_AMOUNT);
        uint256 cap = shares - almCore.DEAD_SHARES_() - 1;
        vm.prank(factory);
        almCore.setPerUserCap(cap);
        token0.mint(factory, Constants.SEED_AMOUNT);
        token1.mint(factory, Constants.SEED_AMOUNT);

        vm.startPrank(factory);
        token0.approve(address(almCore), Constants.SEED_AMOUNT);
        token1.approve(address(almCore), Constants.SEED_AMOUNT);
        vm.stopPrank();

        // When: The factory calls seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        almCore.seed(Constants.SEED_AMOUNT, Constants.SEED_AMOUNT, shares, users.steward);
    }

    function testFuzz_Revert_seed_InvalidAmounts(
        PoolState memory poolState,
        uint256 amount,
        uint256 shares,
        bool withoutToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured and one of the amounts is zero.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        amount = bound(amount, 0, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);

        // When: Calling seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(ALMAdminExtension.InvalidAmounts.selector);
        almCore.seed(withoutToken0 ? 0 : amount, withoutToken0 ? amount : 0, shares, users.steward);
    }

    function testFuzz_Revert_seed_AboveTheDeltaCeiling(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        bool aboveOn0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured and one amount is more than one delta carries.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        amount0 = aboveOn0
            ? bound(amount0, Constants.MAX_FUZZED_AMOUNT + 1, type(uint128).max)
            : bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = aboveOn0
            ? bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT)
            : bound(amount1, Constants.MAX_FUZZED_AMOUNT + 1, type(uint128).max);
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(factory, amount0);
        token1.mint(factory, amount1);

        vm.startPrank(factory);
        token0.approve(address(almCore), amount0);
        token1.approve(address(almCore), amount1);
        vm.stopPrank();

        // When: The caller calls seed().
        // Then: It reverts.
        vm.prank(factory);
        vm.expectRevert(SafeCastLib.Overflow.selector);
        almCore.seed(amount0, amount1, shares, users.steward);
    }

    function testFuzz_Success_seed(PoolState memory poolState, uint256 amount0, uint256 amount1, uint256 shares)
        public
    {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured and the caller holds a seed of both tokens.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        uint160 sqrtPrice = sqrtPriceX96(pool);
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        uint256 value = FixedPointMathLib.fullMulDiv(amount0, uint256(sqrtPrice) * sqrtPrice, 1 << 192) + amount1;
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(factory, amount0);
        token1.mint(factory, amount1);

        // When: The caller calls seed().
        vm.startPrank(factory);
        token0.approve(address(almCore), amount0);
        token1.approve(address(almCore), amount1);
        vm.expectEmit(address(almCore));
        emit IALMCoreEvents.Seeded(users.steward, shares, amount0, amount1);
        almCore.seed(amount0, amount1, shares, users.steward);
        vm.stopPrank();

        // Then: The dead shares are burned to address(1) and the rest is the caller's.
        assertEq(almCore.totalSupply(), shares);
        assertEq(almCore.balanceOf(address(1)), Constants.DEAD_SHARES);
        assertEq(almCore.balanceOf(users.steward), shares - Constants.DEAD_SHARES);

        // And: Requests are priced at the seed's supply per value, in token1 at spot.
        (uint256 supplyPerValueX128, uint160 rateSqrtPriceX96) = almCore.lastExchangeRate_();
        assertEq(rateSqrtPriceX96, sqrtPrice);
        assertEq(supplyPerValueX128, FixedPointMathLib.fullMulDivUp(shares, 1 << 128, value));
    }

    function testFuzz_Success_seed_PerUserCapAtTheReceiversPart(PoolState memory poolState, uint256 multiple) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Shares a multiple of 2^20, and a per user cap of the receiver's part.
        multiple = bound(multiple, 1, Constants.MAX_FUZZED_AMOUNT >> 20);
        uint256 shares = multiple << 20;
        vm.startPrank(factory);
        almCore.setPerUserCap(shares - almCore.DEAD_SHARES_());
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        token0.mint(factory, Constants.SEED_AMOUNT);
        token1.mint(factory, Constants.SEED_AMOUNT);

        // When: The factory seeds.
        vm.startPrank(factory);
        token0.approve(address(almCore), Constants.SEED_AMOUNT);
        token1.approve(address(almCore), Constants.SEED_AMOUNT);
        almCore.seed(Constants.SEED_AMOUNT, Constants.SEED_AMOUNT, shares, users.steward);
        vm.stopPrank();

        // Then: The receiver holds its part.
        assertEq(almCore.balanceOf(users.steward), shares - almCore.DEAD_SHARES_());
    }

    function testFuzz_Success_seed_CreditsBuffer(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: The vault is configured and the caller holds both tokens.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(factory, amount0);
        token1.mint(factory, amount1);

        // When: The caller calls seed().
        vm.startPrank(factory);
        token0.approve(address(almCore), amount0);
        token1.approve(address(almCore), amount1);
        almCore.seed(amount0, amount1, shares, users.steward);
        vm.stopPrank();

        // Then: Both amounts are pulled into the buffer.
        uint256 buffer0 = almCore.bufferAmount0();
        uint256 buffer1 = almCore.bufferAmount1();
        assertEq(buffer0, amount0);
        assertEq(buffer1, amount1);
        assertEq(token0.balanceOf(address(almCore)), amount0);
        assertEq(token1.balanceOf(address(almCore)), amount1);
        assertEq(token0.balanceOf(users.steward), 0);
        assertEq(token1.balanceOf(users.steward), 0);
    }

    function testFuzz_Success_seed_AbsorbsRewardDonation(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        uint256 donation
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A reward token donation landed before the vault was initialized.
        donation = bound(donation, 1, Constants.MAX_FUZZED_AMOUNT);
        deal(almCore.REWARD_TOKEN_(), address(almCore), donation);
        uint256 fee = donation * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();

        // And: The vault is configured and the factory holds a seed of both tokens.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(factory, amount0);
        token1.mint(factory, amount1);

        // When: The factory calls seed().
        vm.startPrank(factory);
        token0.approve(address(almCore), amount0);
        token1.approve(address(almCore), amount1);
        almCore.seed(amount0, amount1, shares, users.steward);
        vm.stopPrank();

        // Then: The donation is absorbed by the high-water mark and credited to nobody.
        assertEq(almCore.rewardPerShare_(), 0);
        assertEq(
            almCore.getPendingReward(users.steward)
                + almCore.balanceOf(users.steward)
                    .fullMulDiv(almCore.rewardPerShare_() - almCore.getRewardSnapshot(users.steward), 1e18),
            0
        );

        // And: The donation is measured, the high water holds it net of the fee.
        assertEq(almCore.getLastRewardBalance(), donation);
        assertEq(almCore.getRewardHighWater(), donation - fee);
    }

    function testFuzz_Success_seed_AbsorbsTheGaugeEarnedOnAnyChainStatus(
        PoolState memory poolState,
        uint256 amount0,
        uint256 amount1,
        uint256 shares,
        uint256 earned,
        uint256 status
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: Emissions the gauge reports for the core before it was initialized.
        earned = bound(earned, 1, Constants.MAX_FUZZED_AMOUNT);
        mockEarned(gauge, address(almCore), earned);
        uint256 net = earned - earned * almCore.protocolEmissionFeeBps_() / almCore.BPS_DENOMINATOR_();

        // And: Any chain status.
        setAnyStatus(status);

        // And: The vault is configured and the factory holds a seed of both tokens.
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();
        amount0 = bound(amount0, 1, Constants.MAX_FUZZED_AMOUNT);
        amount1 = bound(amount1, 1, Constants.MAX_FUZZED_AMOUNT);
        shares = bound(shares, almCore.DEAD_SHARES_() + 1, Constants.MAX_FUZZED_AMOUNT);
        token0.mint(factory, amount0);
        token1.mint(factory, amount1);

        // When: The factory calls seed().
        vm.startPrank(factory);
        token0.approve(address(almCore), amount0);
        token1.approve(address(almCore), amount1);
        almCore.seed(amount0, amount1, shares, users.steward);
        vm.stopPrank();

        // Then: The high water takes the reward on any chain status, none credited.
        assertEq(almCore.getRewardHighWater(), net);
        assertEq(almCore.rewardPerShare_(), 0);
        assertEq(
            almCore.getPendingReward(users.steward)
                + almCore.balanceOf(users.steward)
                    .fullMulDiv(almCore.rewardPerShare_() - almCore.getRewardSnapshot(users.steward), 1e18),
            0
        );
    }
}

/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { ALMVaultSyncExtension } from "../../utils/extensions/ALMVaultSyncExtension.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "maxMint" of contract "ALMVaultSync".
 */
contract MaxMint_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using ALMCoreViewLogic for IALMCore;
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_maxMint_CoreNotDeployed(PoolState memory poolState, bool isToken0, address receiver)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading maxMint() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).maxMint(receiver);
    }

    function testFuzz_Success_maxMint_ZeroWhenNotInitialized(
        PoolState memory poolState,
        address receiver,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Reading maxMint.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxMint(receiver), 0);
    }

    function testFuzz_Success_maxMint_ZeroWhenPaused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address receiver,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, paused by the factory.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        vm.prank(factory);
        vault.setPaused(true);

        // When: Reading maxMint.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxMint(receiver), 0);
    }

    function testFuzz_Success_maxMint_ZeroWhenTheCoreIsPaused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address receiver,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, whose core the factory paused.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        vm.prank(factory);
        almCore.pause();

        // When: Reading maxMint.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxMint(receiver), 0);
    }

    function testFuzz_Success_maxMint_ZeroOutsideTheDeviationBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        address receiver,
        bool isToken0,
        uint256 maxSwapCostBps,
        uint256 maxSpotFromTwap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot pushed within the block by ten times a 1% sale.
        uint256 amountIn = (isToken0
                ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
        .fullMulDiv(10 * Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR);
        ERC20Mock(vault.asset()).mint(users.unprivilegedAddress, amountIn);
        pushPrice(pool, users.unprivilegedAddress, isToken0, amountIn);

        // And: A band between spot and the TWAP narrower than spot's distance from it.
        setSpotFromTwap(outsideBand(maxSpotFromTwap, spotFromTwap(false)));

        // When: Reading maxMint.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxMint(receiver), 0);
    }

    function testFuzz_Success_maxMint_IsTheRemainingCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint96 balance,
        uint96 escrowed,
        uint96 pending,
        uint256 totalRoom,
        uint256 perUserCap,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A receiver with a balance, escrowed shares and pending shares.
        address receiver = users.unprivilegedAddress;
        almCore.mintShares(receiver, balance);
        almCore.mintShares(address(almCore), escrowed);
        almCore.setClaimableShares(receiver, escrowed);
        almCore.setPendingShares(receiver, pending);

        // And: The shares the pool's next swap step can buy for, with no cap binding.
        setUncapped();
        uint256 stepRoom = IALMSyncExtension(address(vault)).maxMint(receiver);

        // And: A total cap a fuzzed room above the supply, and a fuzzed per user cap.
        uint256 supply = almCore.totalSupply();
        totalRoom = bound(totalRoom, 0, type(uint128).max - supply);
        perUserCap = bound(perUserCap, 0, type(uint128).max);
        vm.startPrank(factory);
        almCore.setTotalCap(supply + totalRoom);
        almCore.setPerUserCap(perUserCap);
        vm.stopPrank();

        // When: Reading maxMint.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(receiver);

        // Then: It is the least of the total cap, per user cap and step rooms.
        uint256 capBalance = uint256(balance) + escrowed + pending;
        uint256 userRoom = perUserCap > capBalance ? perUserCap - capBalance : 0;
        assertEq(shares, FixedPointMathLib.min(FixedPointMathLib.min(totalRoom, userRoom), stepRoom));
    }

    function testFuzz_Success_maxMint_ZeroForTheCore(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // When: Reading maxMint for the core.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxMint(address(almCore)), 0);
    }

    function testFuzz_Success_maxMint_TakesTheHeadroom(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 pending,
        uint256 room,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A receiver with pending shares, its per user cap room within maxMint.
        uint256 stepRoom = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(stepRoom > 0);
        room = bound(room, 1, stepRoom);
        setPerUserCapAbovePendingShares(users.unprivilegedAddress, pending, room);

        // When: Reading maxMint.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);

        // Then: It is the room the per user cap leaves above the receiver's cap balance.
        assertEq(shares, room);
    }

    function testFuzz_Success_maxMint_ZeroWhileTheCoreIsLocked(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // When: A router reads maxMint while a keeper plan holds the core's lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(IALMSyncExtension.maxMint, (users.unprivilegedAddress)));

        // Then: It is zero, and does not revert.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), 0);

        // And: Outside the plan the same read is above zero, so the lock alone zeroed it.
        assertGt(IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxMint_ZeroWithoutPoolLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A pool without active liquidity at spot.
        vm.mockCall(address(pool), abi.encodeCall(ICLPool.liquidity, ()), abi.encode(uint128(0)));

        // When: Reading maxMint.
        // Then: It is zero, there being nothing to buy the non-asset from.
        assertEq(IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxMint_ZeroBelowTheToken0Floor(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 sqrtPrice,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded token1 vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, false);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A spot and TWAP whose squared price over 2^96 floors to zero.
        sqrtPrice = bound(sqrtPrice, TickMath.MIN_SQRT_PRICE, Constants.SQRT_Q96 - 1);
        int24 tick = TickMath.getTickAtSqrtPrice(uint160(sqrtPrice));
        vm.mockCall(
            address(pool),
            abi.encodeCall(ICLPool.slot0, ()),
            abi.encode(uint160(sqrtPrice), tick, uint16(0), uint16(1), uint16(1), true)
        );
        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[1] = int56(tick) * int56(uint56(Constants.TWAP_WINDOW));
        vm.mockCall(address(pool), abi.encodeWithSelector(ICLPool.observe.selector), abi.encode(tickCumulatives));

        // When: Reading maxMint.
        // Then: It is zero, the core's token0 amounts dividing by that floor.
        assertEq(IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxMint_ZeroWithSpotBelowTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps,
        uint256 maxSpotFromTwap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The receiver may mint before the band narrows.
        uint256 room = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        assertGt(room, 0);

        // And: A trade that pushed spot a tick spacing below the TWAP.
        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);

        // And: A band between spot and the TWAP narrower than spot's distance from it.
        setSpotFromTwap(outsideBand(maxSpotFromTwap, spotFromTwap(false)));

        // When: Calling maxMint().
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);

        // Then: Spot sits outside the band, so nothing may be minted.
        assertEq(shares, 0);
    }

    function testFuzz_Success_maxMint_ZeroWithSpotAboveTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps,
        uint256 maxSpotFromTwap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The receiver may mint before the band narrows.
        uint256 room = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        assertGt(room, 0);

        // And: A trade that pushed spot a tick spacing above the TWAP.
        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickCurrent + poolState.tickSpacing);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickCurrent + poolState.tickSpacing);

        // And: A band between spot and the TWAP narrower than spot's distance from it.
        setSpotFromTwap(outsideBand(maxSpotFromTwap, spotFromTwap(false)));

        // When: Calling maxMint().
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);

        // Then: Spot sits outside the band, so nothing may be minted.
        assertEq(shares, 0);
    }

    function testFuzz_Success_maxMint_WithinTheBand(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps,
        uint256 maxSpotFromTwap
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A trade that moved the price a tick spacing down.
        fundActorForTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);
        pushPriceToTick(pool, users.unprivilegedAddress, poolState.tickCurrent - poolState.tickSpacing);

        // And: A band between spot and the TWAP holding a further tick spacing past spot.
        {
            uint256 mean = almCore.meanSqrtPriceX96_();
            uint256 beyond = TickMath.getSqrtPriceAtTick(currentTick(pool) - poolState.tickSpacing);
            maxSpotFromTwap = bound(maxSpotFromTwap, mean.fullMulDivUp(1e18, beyond) - 1e18, type(uint64).max);
            setSpotFromTwap(maxSpotFromTwap);
        }

        // When: Calling maxMint().
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);

        // Then: Spot stays inside the band, so the receiver may mint.
        assertGt(shares, 0);
        uint256 ratio = uint256(sqrtPriceX96(pool)) * 1e18 / almCore.meanSqrtPriceX96_();
        assertLe(ratio, 1e18 + maxSpotFromTwap);
        assertGe(ratio + maxSpotFromTwap, 1e18);
    }

    function testFuzz_Success_maxMint_NoTrade(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint32 elapsed,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);
        ALMVaultSyncExtension vault = vaultExtension(isToken0);

        // And: A band spanning spot's tick, read after the window ran.
        vm.warp(
            vm.getBlockTimestamp() + bound(elapsed, Constants.TWAP_WINDOW, type(uint32).max - vm.getBlockTimestamp())
        );
        int24 tick = currentTick(pool);
        uint256 oneTick = FixedPointMathLib.fullMulDivUp(
            TickMath.getSqrtPriceAtTick(tick + 1), 1e18, TickMath.getSqrtPriceAtTick(tick)
        ) - 1e18;
        setSpotFromTwap(oneTick);

        // When: Checking whether the vault can quote.
        bool quotable = vault.quotable_();

        // Then: Spot sits in the tick the TWAP reports, so the vault quotes.
        assertTrue(quotable);
        assertEq(TickMath.getSqrtPriceAtTick(currentTick(pool)), almCore.meanSqrtPriceX96_());
    }

    function testFuzz_Success_maxMint_ItsMintSucceedsAtSpot(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The most the caller may mint, and a caller funded far above what it costs.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(shares > 0);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        uint256 balanceBefore = almCore.balanceOf(users.unprivilegedAddress);

        // When: The caller mints it.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress) - balanceBefore, shares);
    }

    function testFuzz_Success_maxMint_ItsMintSucceedsAfterAPricePush(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        bool zeroForOne,
        uint256 amountIn,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot pushed either way by at most a 1% sale.
        uint256 ceiling = (zeroForOne
                ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
        .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR);
        amountIn = bound(amountIn, 1, ceiling);
        ERC20Mock(zeroForOne ? pool.token0() : pool.token1()).mint(users.unprivilegedAddress, amountIn);
        pushPrice(pool, users.unprivilegedAddress, zeroForOne, amountIn);

        // And: The most the caller may mint, and a caller funded far above what it costs.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(shares > 0);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        uint256 balanceBefore = almCore.balanceOf(users.unprivilegedAddress);

        // When: The caller mints it.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress) - balanceBefore, shares);
    }

    function testFuzz_Success_maxMint_ItsMintSucceedsWithinTheSwapCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps =
            bound(maxSwapCostBps, FixedPointMathLib.divUp(poolState.fee, 100) + 1, ConfigLib.BPS_DENOMINATOR - 1);

        // And: A seeded vault holding a range, under that cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheRounding(
            coreState, poolState, range, isToken0, maxSwapCostBps * 100 - poolState.fee, 0
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: The most the caller may mint, and a caller funded far above what it costs.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        uint256 sqrtPriceStart = sqrtPriceX96(pool);

        // When: The caller mints it through the plain signature.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);

        // And: Its swap ended at or inside the swap cost's band.
        uint256 scale = 1e18 + (maxSwapCostBps * 100 - pool.fee()) * 5e11;
        if (isToken0) assertGe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDivUp(1e18, scale));
        else assertLe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDiv(scale, 1e18));
    }

    function testFuzz_Success_maxMint_ZeroWhenTheSwapCostIsWithinTheFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A vault seeded with it, its non-asset buffer over a wei per range.
        {
            uint256 least = almCore.getRangesLength() + 2;
            givenValidCoreState(coreState, poolState, range, 0, isToken0 ? 0 : least, isToken0 ? least : 0);
        }
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A max swap cost of at most the pool's fee.
        maxSwapCostBps = bound(maxSwapCostBps, 0, poolState.fee / 100);
        setMaxSwapCost(maxSwapCostBps);

        // When: Reading maxMint.
        // Then: It is zero, no buy fitting within the fee.
        assertEq(IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxMint_ZeroWhenTheFeeCannotBeRead(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, with room under the caps.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        assertGt(IALMCore(address(almCore)).maxMint(users.unprivilegedAddress), 0);

        // And: A pool whose fee read reverts.
        vm.mockCallRevert(address(pool), abi.encodeWithSelector(IMetadexCLPool.fee.selector), "");

        // When: Reading maxMint.
        // Then: It is zero, and does not revert.
        assertEq(IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress), 0);
    }
}

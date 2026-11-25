/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "../../ALMCore/_ALMCore.fuzz.t.sol";
import { ALMCoreViewLogicExtension } from "../../../utils/extensions/ALMCoreViewLogicExtension.sol";
import { Constants } from "../../../utils/Constants.sol";
import { ERC20Mock } from "../../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "quotable" of library "ALMCoreViewLogic".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract Quotable_ALMCoreViewLogic_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_quotable_OLD(
        PoolState memory poolState,
        uint256 shares,
        uint256 twapWindow,
        bool assetIsToken0
    ) public {
        // Given: A core with supply on a pool at a fuzzed price, one TWAP window old.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.mintShares(users.steward, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));

        // And: A TWAP window longer than the pool's observation history.
        twapWindow = bound(twapWindow, uint256(Constants.TWAP_WINDOW) + 1, vm.getBlockTimestamp());
        vm.prank(factory);
        almCore.setDeviation(
            uint32(twapWindow), Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );

        // When: Reading whether a vault can quote.
        // Then: It reverts, the pool has no observation that far back.
        vm.expectRevert(bytes("OLD"));
        coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, false);
    }

    function testFuzz_Success_quotable_NotForAPausedVault(
        PoolState memory poolState,
        uint256 shares,
        bool assetIsToken0
    ) public {
        // Given: A core with supply on a pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.mintShares(users.steward, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));

        // When: Reading whether a paused vault can quote.
        (bool isQuotable, uint160 spot, uint256 sqrtPriceLimitX96) =
            coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, true);

        // Then: It cannot, with no price.
        assertFalse(isQuotable);
        assertEq(spot, 0);
        assertEq(sqrtPriceLimitX96, 0);
    }

    function testFuzz_Success_quotable_NotWithoutSupply(PoolState memory poolState, bool assetIsToken0) public {
        // Given: A core without supply on a pool at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Reading whether a vault can quote.
        (bool isQuotable, uint160 spot, uint256 sqrtPriceLimitX96) =
            coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, false);

        // Then: It cannot, with no price.
        assertFalse(isQuotable);
        assertEq(spot, 0);
        assertEq(sqrtPriceLimitX96, 0);
    }

    function testFuzz_Success_quotable_NotForAPausedVaultDuringAPlan(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        bool assetIsToken0
    ) public {
        // Given: A seeded vault holding a range.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setCoreState(coreState);
        setRangeState(range);

        // When: A router reads if a paused vault can quote during a keeper plan.
        (bool success, bytes memory result) = readDuringPlan(
            address(coreViewLogic),
            abi.encodeCall(ALMCoreViewLogicExtension.quotable, (address(almCore), address(pool), assetIsToken0, true))
        );

        // Then: It cannot, with no price.
        assertTrue(success);
        (bool isQuotable, uint160 spot, uint256 sqrtPriceLimitX96) = abi.decode(result, (bool, uint160, uint256));
        assertFalse(isQuotable);
        assertEq(spot, 0);
        assertEq(sqrtPriceLimitX96, 0);
    }

    function testFuzz_Success_quotable_OneBelowTheLowerEdge(
        PoolState memory poolState,
        uint256 shares,
        uint256 deviation,
        bool assetIsToken0
    ) public {
        // Given: A core with supply on a pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.mintShares(users.steward, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band from one tick's step to the wide deviation around the TWAP.
        deviation = bound(
            deviation,
            FixedPointMathLib.divUp((TickMath.getSqrtPriceAtTick(poolState.tickCurrent + 1) - mean) * 1e18, mean),
            Constants.WIDE_DEVIATION
        );
        setSpotFromTwap(deviation);

        // And: Spot moved within the block to one below the band's lower edge.
        uint160 edge = uint160(FixedPointMathLib.divUp(mean * 1e18, 1e18 + deviation));
        ERC20Mock(pool.token0()).mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        swapAsActor(
            pool, users.unprivilegedAddress, pool.token0(), pool.token1(), Constants.MAX_FUZZED_AMOUNT, edge - 1
        );

        // When: Reading whether a vault can quote.
        (bool isQuotable,,) = coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, false);

        // Then: It cannot.
        assertFalse(isQuotable);
    }

    function testFuzz_Success_quotable_OneAboveTheUpperEdge(
        PoolState memory poolState,
        uint256 shares,
        uint256 deviation,
        bool assetIsToken0
    ) public {
        // Given: A core with supply on a pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.mintShares(users.steward, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band from one tick's step to the wide deviation around the TWAP.
        deviation = bound(
            deviation,
            FixedPointMathLib.divUp((TickMath.getSqrtPriceAtTick(poolState.tickCurrent + 1) - mean) * 1e18, mean),
            Constants.WIDE_DEVIATION
        );
        setSpotFromTwap(deviation);

        // And: Spot moved within the block to one above the band's upper edge.
        uint160 edge = uint160(mean * (1e18 + deviation) / 1e18);
        ERC20Mock(pool.token1()).mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        swapAsActor(
            pool, users.unprivilegedAddress, pool.token1(), pool.token0(), Constants.MAX_FUZZED_AMOUNT, edge + 1
        );

        // When: Reading whether a vault can quote.
        (bool isQuotable,,) = coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, false);

        // Then: It cannot.
        assertFalse(isQuotable);
    }

    function testFuzz_Success_quotable_AtTheLowerEdge(
        PoolState memory poolState,
        uint256 shares,
        uint256 deviation,
        bool assetIsToken0
    ) public {
        // Given: A core with supply on a pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.mintShares(users.steward, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band from one tick's step to the wide deviation around the TWAP.
        deviation = bound(
            deviation,
            FixedPointMathLib.divUp((TickMath.getSqrtPriceAtTick(poolState.tickCurrent + 1) - mean) * 1e18, mean),
            Constants.WIDE_DEVIATION
        );
        setSpotFromTwap(deviation);

        // And: Spot moved within the block to the band's lower edge.
        uint160 lower = uint160(FixedPointMathLib.divUp(mean * 1e18, 1e18 + deviation));
        ERC20Mock(pool.token0()).mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        swapAsActor(pool, users.unprivilegedAddress, pool.token0(), pool.token1(), Constants.MAX_FUZZED_AMOUNT, lower);

        // When: Reading whether a vault can quote.
        (bool isQuotable, uint160 spot, uint256 sqrtPriceLimitX96) =
            coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, false);

        // Then: It can, at spot, limited at the band edge a non-asset buy moves to.
        assertTrue(isQuotable);
        assertEq(spot, lower);
        assertEq(sqrtPriceLimitX96, assetIsToken0 ? lower : mean * (1e18 + deviation) / 1e18);
    }

    function testFuzz_Success_quotable_AtTheUpperEdge(
        PoolState memory poolState,
        uint256 shares,
        uint256 deviation,
        bool assetIsToken0
    ) public {
        // Given: A core with supply on a pool at a fuzzed price that has seen no trade.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        almCore.mintShares(users.steward, bound(shares, 1, Constants.MAX_FUZZED_AMOUNT));
        uint256 mean = TickMath.getSqrtPriceAtTick(poolState.tickCurrent);

        // And: A ratio band from one tick's step to the wide deviation around the TWAP.
        deviation = bound(
            deviation,
            FixedPointMathLib.divUp((TickMath.getSqrtPriceAtTick(poolState.tickCurrent + 1) - mean) * 1e18, mean),
            Constants.WIDE_DEVIATION
        );
        setSpotFromTwap(deviation);

        // And: Spot moved within the block to the band's upper edge.
        uint160 upper = uint160(mean * (1e18 + deviation) / 1e18);
        ERC20Mock(pool.token1()).mint(users.unprivilegedAddress, Constants.MAX_FUZZED_AMOUNT);
        swapAsActor(pool, users.unprivilegedAddress, pool.token1(), pool.token0(), Constants.MAX_FUZZED_AMOUNT, upper);

        // When: Reading whether a vault can quote.
        (bool isQuotable, uint160 spot, uint256 sqrtPriceLimitX96) =
            coreViewLogic.quotable(address(almCore), address(pool), assetIsToken0, false);

        // Then: It can, at spot, limited at the band edge a non-asset buy moves to.
        assertTrue(isQuotable);
        assertEq(spot, upper);
        assertEq(sqrtPriceLimitX96, assetIsToken0 ? FixedPointMathLib.divUp(mean * 1e18, 1e18 + deviation) : upper);
    }
}

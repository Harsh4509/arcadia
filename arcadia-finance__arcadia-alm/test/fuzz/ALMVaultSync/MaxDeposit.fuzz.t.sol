/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore } from "../../../src/core/ALMCore.sol";
import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMCore } from "../../../src/interfaces/IALMCore.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";

/**
 * @notice Fuzz tests for the function "maxDeposit" of contract "ALMVaultSync".
 */
contract MaxDeposit_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
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

    function testFuzz_Revert_maxDeposit_CoreNotDeployed(PoolState memory poolState, bool isToken0, address receiver)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading maxDeposit() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        IALMSyncExtension(vault).maxDeposit(receiver);
    }

    function testFuzz_Success_maxDeposit_ZeroWhenNotInitialized(
        PoolState memory poolState,
        address receiver,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // When: Reading maxDeposit.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(receiver), 0);
    }

    function testFuzz_Success_maxDeposit_ZeroWhenPaused(
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

        // When: Reading maxDeposit.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(receiver), 0);
    }

    function testFuzz_Success_maxDeposit_ZeroWhenTheCoreIsPaused(
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

        // When: Reading maxDeposit.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(receiver), 0);
    }

    function testFuzz_Success_maxDeposit_ZeroOutsideTheDeviationBand(
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

        // When: Reading maxDeposit.
        // Then: It is zero.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(receiver), 0);
    }

    function testFuzz_Success_maxDeposit_ItsDepositMintsWithinTheCapRoom(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A max swap cost above the pool's fee.
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);

        // And: A seeded vault holding a range, under that cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheRounding(
            coreState, poolState, range, isToken0, maxSwapCostBps * 100 - poolState.fee, 0
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: The most a deposit takes, the cap room, and its holder.
        uint256 assets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 room = IALMCore(address(almCore)).maxMint(users.unprivilegedAddress);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits it, with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: Its swap stays inside the band, and it mints at most the cap room.
        assertLe(shares, room);
    }

    function testFuzz_Success_maxDeposit_ZeroWhileTheCoreIsLocked(
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

        // When: A router reads maxDeposit while a keeper plan holds the core's lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(IALMSyncExtension.maxDeposit, (users.unprivilegedAddress)));

        // Then: It is zero, and does not revert.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), 0);
    }

    function testFuzz_Success_maxDeposit_ZeroWhenTheFeeCannotBeRead(
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

        // When: Reading maxDeposit.
        // Then: It is zero, and does not revert.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxDeposit_ItsDepositMintsWithinTheCapRoomAfterAPricePush(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 maxSwapCostBps,
        bool isToken0,
        bool zeroForOne,
        uint256 amountIn
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A max swap cost above the pool's fee.
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);

        // And: A seeded vault holding a range, under that cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheRounding(
            coreState, poolState, range, isToken0, maxSwapCostBps * 100 - poolState.fee, 0
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: Spot pushed either way by at most a 1% sale.
        uint256 ceiling = (zeroForOne
                ? uint256(pool.liquidity()).fullMulDiv(1 << 96, sqrtPriceX96(pool))
                : uint256(pool.liquidity()).fullMulDiv(sqrtPriceX96(pool), 1 << 96))
        .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR);
        amountIn = bound(amountIn, 1, ceiling);
        ERC20Mock(zeroForOne ? pool.token0() : pool.token1()).mint(users.unprivilegedAddress, amountIn);
        pushPrice(pool, users.unprivilegedAddress, zeroForOne, amountIn);

        // And: The most a deposit takes, the cap room, and its holder.
        uint256 assets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 room = IALMCore(address(almCore)).maxMint(users.unprivilegedAddress);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));

        // When: The caller deposits it, with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, 0);

        // Then: It mints at most the cap room.
        assertLe(shares, room);
    }

    function testFuzz_Success_maxDeposit_ItsDepositSucceedsWithinTheSwapCost(
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

        // And: The most a deposit takes, and its holder.
        uint256 assets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));
        uint256 sqrtPriceStart = sqrtPriceX96(pool);
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller deposits it through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress);

        // Then: It minted the shares to the caller.
        assertEq(almCore.totalSupply(), supplyBefore + shares);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);

        // And: Its swap ended at or inside the swap cost's band.
        uint256 scale = 1e18 + (maxSwapCostBps * 100 - pool.fee()) * 5e11;
        if (isToken0) assertGe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDivUp(1e18, scale));
        else assertLe(sqrtPriceX96(pool), sqrtPriceStart.fullMulDiv(scale, 1e18));
    }

    function testFuzz_Success_maxDeposit_ZeroWithADustNonAssetLegWithinTheRounding(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 room,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool where a price step moves under an eighth of the mint's rounding.
        givenValidPoolState(poolState);
        poolState.liquidityPool = uint128(
            FixedPointMathLib.min(poolState.liquidityPool, poolState.sqrtPrice / Constants.PRICE_STEP_ROUNDING_DIVISOR)
        );
        setPoolState(poolState, false);

        // And: A max swap cost above the pool's fee, and the ticks of its band.
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);
        int24 gap = bandTicks(poolState, maxSwapCostBps);

        // And: A vault holding the non-asset only as a leg in a quarter of its rounding.
        uint256 rounding0 = uint256(1 << 96).divUp(poolState.sqrtPrice) + 3;
        uint256 rounding1 = poolState.sqrtPrice.divUp(1 << 96) + 3;
        leg = bound(leg, 1, (isToken0 ? rounding1 : rounding0) / 4);
        givenValidDustState(coreState, poolState, range, !isToken0, leg, gap);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: A cap room of at least a share, worth at most 2^48 times either rounding.
        {
            uint256 most = isToken0
                ? FixedPointMathLib.min(
                    rounding0 << 48, CLMath.convert(poolState.sqrtPrice, false, rounding1 << 48, false)
                )
                : FixedPointMathLib.min(
                    rounding1 << 48, CLMath.convert(poolState.sqrtPrice, true, rounding0 << 48, false)
                );
            uint256 ceiling =
                most.fullMulDiv(almCore.totalSupply(), IALMSyncExtension(address(vault)).totalAssets() + 1);
            // And: Where a share is worth over that, a hole no bound expresses.
            vm.assume(ceiling > 0);
            room = bound(room, 1, ceiling);
            vm.prank(factory);
            almCore.setPerUserCap(room);
        }

        // When: Reading maxDeposit.
        // Then: It is zero, a capped deposit moving less of that token than the rounding.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxDeposit_ItsDepositMintsWithADustAssetLeg(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 room,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool where a price step moves under an eighth of the mint's rounding.
        givenValidPoolState(poolState);
        poolState.liquidityPool = uint128(
            FixedPointMathLib.min(poolState.liquidityPool, poolState.sqrtPrice / Constants.PRICE_STEP_ROUNDING_DIVISOR)
        );
        setPoolState(poolState, false);

        // And: A max swap cost above the pool's fee, and the ticks of its band.
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);
        int24 gap = bandTicks(poolState, maxSwapCostBps);

        // And: A vault holding the asset only as a leg within a quarter of its rounding.
        uint256 rounding0 = uint256(1 << 96).divUp(poolState.sqrtPrice) + 3;
        uint256 rounding1 = poolState.sqrtPrice.divUp(1 << 96) + 3;
        leg = bound(leg, 1, (isToken0 ? rounding0 : rounding1) / 4);
        givenValidDustState(coreState, poolState, range, isToken0, leg, gap);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: A cap room of at least a share, worth at most 2^48 times either rounding.
        {
            uint256 most = isToken0
                ? FixedPointMathLib.min(
                    rounding0 << 48, CLMath.convert(poolState.sqrtPrice, false, rounding1 << 48, false)
                )
                : FixedPointMathLib.min(
                    rounding1 << 48, CLMath.convert(poolState.sqrtPrice, true, rounding0 << 48, false)
                );
            uint256 ceiling =
                most.fullMulDiv(almCore.totalSupply(), IALMSyncExtension(address(vault)).totalAssets() + 1);
            // And: Where a share is worth over that, a hole no bound expresses.
            vm.assume(ceiling > 0);
            room = bound(room, 1, ceiling);
            vm.prank(factory);
            almCore.setPerUserCap(room);
        }

        // And: A caller holding the most a deposit takes, its preview above zero.
        uint256 assets = IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress);
        uint256 quoted = IALMSyncExtension(address(vault)).previewDeposit(assets);
        // And: Where the dust leg mints nothing, a hole no bound expresses.
        vm.assume(quoted > 0);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), assets, address(vault));
        uint256 balance = (isToken0 ? token1 : token0).balanceOf(address(vault));
        uint256 held = heldOut(isToken0);
        uint256 supply = almCore.totalSupply();

        // When: The caller deposits it with the preview as its minimum.
        vm.recordLogs();
        vm.prank(users.unprivilegedAddress);
        uint256 shares = vault.deposit(assets, users.unprivilegedAddress, quoted);

        // Then: It minted the preview within the room, the dust leg not binding.
        assertEq(shares, quoted);
        assertLe(shares, room);

        // And: The vault kept at most the stranded non-asset of the deposit's buy.
        (, uint256 bought) = swapAmounts(address(vault));
        assertLe(
            (isToken0 ? token1 : token0).balanceOf(address(vault)) - balance,
            strandedOut(isToken0, held, supply, shares, bought)
        );
    }

    function testFuzz_Success_maxDeposit_ZeroWhenTheSwapCostIsWithinTheFee(
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

        // When: Reading maxDeposit.
        // Then: It is zero, no swap fitting within the fee.
        assertEq(IALMSyncExtension(address(vault)).maxDeposit(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_maxDeposit_ItsDepositMintsNothingWhenTheBandCapsItUnderAShare(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool at a fuzzed price, and a max swap cost above its fee.
        givenValidPoolState(poolState);
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);
        uint256 scale = 1e18 + (maxSwapCostBps * 100 - poolState.fee) * 5e11;

        // And: Depth whose band buys under a millionth of an eighth of an amount.
        {
            uint256 edge = poolState.sqrtPrice.fullMulDiv(1e18, scale);
            uint256 ceiling = (Constants.MAX_FUZZED_AMOUNT / Constants.POOL_DEPTH_DIVISOR / Constants.DEAD_SHARES - 1)
            .fullMulDiv(1 << 96, poolState.sqrtPrice - edge);
            poolState.liquidityPool = uint128(
                bound(
                    poolState.liquidityPool,
                    Constants.MIN_FUZZED_LIQUIDITY,
                    FixedPointMathLib.min(poolState.liquidityPool, ceiling)
                )
            );
        }
        setPoolState(poolState, false);
        uint256 bandOut = SqrtPriceMath.getAmount1Delta(
            uint160(poolState.sqrtPrice.fullMulDiv(1e18, scale)),
            uint160(poolState.sqrtPrice),
            poolState.liquidityPool,
            true
        );

        // And: A range below the band, a token0 leg, and a band of token1 per dead share.
        givenValidDustState(coreState, poolState, range, true, leg, bandTicks(poolState, maxSwapCostBps));
        givenValidCoreState(coreState, poolState, range, 0, 0, Constants.DEAD_SHARES * (bandOut + 1) + 1);

        // And: A supply whose share is worth more token1 than the band buys.
        {
            (, uint256 held1,,) = stagedAmounts(poolState, range, coreState.buffer0, coreState.buffer1);
            coreState.supply = bound(coreState.supply, Constants.DEAD_SHARES, held1 / (bandOut + 1));
        }

        // And: A token0 vault seeded with it.
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(maxSwapCostBps);

        // When: Reading maxDeposit.
        uint256 max = vault.maxDeposit(users.unprivilegedAddress);

        // Then: It is above zero.
        assertGt(max, 0);

        // And: Its deposit reverts, minting no share.
        fundVaultCaller(users.unprivilegedAddress, address(token0), max, address(vault));
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMCore.ZeroShares.selector);
        vault.deposit(max, users.unprivilegedAddress);
    }
}

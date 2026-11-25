/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { IMetadexCLPool } from "../../../src/interfaces/IMetadexCLPool.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { ShareLib } from "../../../src/core/libraries/state/ShareLib.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Fuzz tests for the function "mint" of contract "ALMVaultSync".
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
contract Mint_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_mint_Paused(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: Anyone mints.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.mint(shares, users.unprivilegedAddress, type(uint256).max);
    }

    function testFuzz_Revert_mint_Paused_BeforeThePlainPreview(
        PoolState memory poolState,
        uint256 amount,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // And: The factory paused it.
        vm.prank(factory);
        vault.setPaused(true);

        // When: Calling the plain mint().
        // Then: It reverts on the pause, before the preview.
        vm.prank(users.steward);
        vm.expectRevert(BaseVault.Paused.selector);
        vault.mint(amount, users.steward);
    }

    function testFuzz_Revert_mint_NotInitialized(
        PoolState memory poolState,
        uint256 shares,
        uint256 maxAssets,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);
        shares = bound(shares, 1, type(uint256).max);

        // When: Anyone mints with a bound of its own.
        // Then: It reverts, there being no supply to cost the shares against.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(FixedPointMathLib.FullMulDivFailed.selector);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);
    }

    function testFuzz_Revert_mint_TotalCapExceeded_OneAboveMaxMint(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
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

        // And: A total cap that leaves a fuzzed room above the supply, within maxMint.
        uint256 stepRoom = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(stepRoom > 0);
        room = bound(room, 1, stepRoom);
        uint256 totalCap = almCore.totalSupply() + room;
        vm.prank(factory);
        almCore.setTotalCap(totalCap);
        uint256 maxAssets = type(uint128).max;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), maxAssets, address(vault));
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress) + 1;

        // When: The caller mints one share more than maxMint reports.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ShareLib.TotalCapExceeded.selector);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);
    }

    function testFuzz_Revert_mint_PerUserCapExceeded_PendingShares(
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

        // And: A seeded vault, and a receiver with pending shares below its per user cap.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        uint256 stepRoom = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is under two shares, a hole no bound expresses.
        vm.assume(stepRoom > 1);
        room = bound(room, 1, stepRoom - 1);
        setPerUserCapAbovePendingShares(users.unprivilegedAddress, pending, room);

        // And: A receiver holding all the asset the token can still mint.
        uint256 maxAssets = type(uint256).max - ERC20Mock(vault.asset()).totalSupply();
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), maxAssets, address(vault));

        // When: The receiver mints one share more than the room.
        // Then: It reverts.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ShareLib.PerUserCapExceeded.selector);
        vault.mint(room + 1, users.unprivilegedAddress, maxAssets);
    }

    function testFuzz_Revert_mint_ExcessiveInput_TheBuyCostsMoreThanThePayment(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        int24 tick,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot, its asset-side edge over a tick inside the band.
        givenValidRangeState(range, poolState, true);
        if (isToken0) {
            range.tickUpper = int24(
                bound(
                    range.tickUpper / poolState.tickSpacing,
                    (poolState.tickCurrent + poolState.tickSpacing) / poolState.tickSpacing,
                    (bandTick(poolState.tickSpacing) - 2) / poolState.tickSpacing
                )
            ) * poolState.tickSpacing;
        } else {
            range.tickLower = int24(
                bound(
                    range.tickLower / poolState.tickSpacing,
                    (2 - bandTick(poolState.tickSpacing)) / poolState.tickSpacing,
                    (poolState.tickCurrent - poolState.tickSpacing) / poolState.tickSpacing
                )
            ) * poolState.tickSpacing;
        }

        // And: A vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot parked past the range on the asset's side, the TWAP caught up.
        tick = isToken0
            ? int24(bound(tick, range.tickUpper + 1, bandTick(poolState.tickSpacing) - 1))
            : int24(bound(tick, -bandTick(poolState.tickSpacing) + 1, range.tickLower - 1));
        parkSpotAt(poolState, range, tick);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: No asset in the buffer, so the core holds only the other token.
        almCore.setBuffers(isToken0 ? 0 : almCore.bufferAmount0(), isToken0 ? almCore.bufferAmount1() : 0);

        // And: The pool reporting no fee to the vault, its quote leaving out the fee.
        vm.mockCall(address(pool), abi.encodeWithSelector(IMetadexCLPool.beforeSwapFee.selector), abi.encode(uint24(0)));

        // And: A mint whose buy stays within the range, a 1% sale and the cap.
        {
            uint256 sqrtPrice = sqrtPriceX96(pool);
            uint256 liquidity = pool.liquidity();
            uint256 held = isToken0 ? almCore.bufferAmount1() : almCore.bufferAmount0();
            {
                (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
                held += isToken0 ? fees1 : fees0;
            }
            {
                Range memory staged = almCore.getRange(0);
                (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                    uint160(sqrtPrice),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                held += isToken0 ? amount1 : amount0;
            }
            uint256 capacity = FixedPointMathLib.min(
                (isToken0 ? liquidity.fullMulDiv(sqrtPrice, 1 << 96) : liquidity.fullMulDiv(1 << 96, sqrtPrice))
                .fullMulDiv(Constants.DEFAULT_SLIPPAGE_BPS, ConfigLib.BPS_DENOMINATOR),
                Constants.MAX_FUZZED_AMOUNT
            );
            {
                uint160 edge = TickMath.getSqrtPriceAtTick(isToken0 ? range.tickUpper : range.tickLower);
                capacity = FixedPointMathLib.min(
                    capacity,
                    isToken0
                        ? SqrtPriceMath.getAmount1Delta(edge, uint160(sqrtPrice), uint128(liquidity), false)
                        : SqrtPriceMath.getAmount0Delta(uint160(sqrtPrice), edge, uint128(liquidity), false)
                );
            }
            uint256 most = FixedPointMathLib.min(
                capacity.zeroFloorSub((isToken0 ? sqrtPrice.divUp(1 << 96) : uint256(1 << 96).divUp(sqrtPrice)) + 3)
                    .fullMulDiv(almCore.totalSupply(), held),
                almCore.totalCap_() - almCore.totalSupply()
            );

            // And: Enough shares that the buy's fee exceeds the quote's wei per range.
            uint256 least = type(uint256).max;
            {
                uint256 heldIn = isToken0
                    ? held.zeroFloorSub(1).fullMulDiv(1 << 96, sqrtPrice).fullMulDiv(1 << 96, sqrtPrice)
                    : held.zeroFloorSub(1).fullMulDiv(sqrtPrice, 1 << 96).fullMulDiv(sqrtPrice, 1 << 96);
                if (heldIn * poolState.fee > 1e6) {
                    least = 1e6 * almCore.totalSupply() / (heldIn * poolState.fee - 1e6) + 1;
                }
            }
            // And: Room where the fee beats the quote's wei, a hole no bound expresses.
            vm.assume(least <= most);
            shares = bound(shares, least, most);
        }

        // And: A funded caller, and the vault holding enough to pay a dearer buy.
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        ERC20Mock(vault.asset()).mint(address(vault), Constants.MAX_FUZZED_AMOUNT);

        // When: The caller mints with no bound of its own.
        // Then: It reverts, the buy's fee taking more than the payment the quote pulled.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.ExcessiveInput.selector);
        vault.mint(shares, users.unprivilegedAddress, type(uint256).max);
    }

    function testFuzz_Revert_mint_ExcessiveInput_NoSwap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxAssets,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A token0 vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot below the range and no token1 buffer, so a mint costs token0 only.
        parkAtTick(pool, users.unprivilegedAddress, range.tickLower - poolState.tickSpacing);
        vm.warp(vm.getBlockTimestamp() + 2 * Constants.TWAP_WINDOW);
        almCore.setBuffers(almCore.bufferAmount0(), 0);

        // And: At most maxMint and an amount's worth of token0, and a funded caller.
        {
            Range memory staged = almCore.getRange(0);
            (uint256 held,) = amountsRoundedUp(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            (uint256 fees0,,) = almCore.getUnstakedPositions();
            uint256 ceiling = FixedPointMathLib.min(
                IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress),
                (Constants.MAX_FUZZED_AMOUNT - uint256(1 << 96).divUp(sqrtPriceX96(pool)) - 3)
                .fullMulDiv(almCore.totalSupply(), held + fees0 + almCore.bufferAmount0())
            );
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(shares, 1, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // And: A bound below the token0 the shares hold, rounded down.
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            (uint256 least,) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                uint128(
                    (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
                    .fullMulDiv(shares, supply)
                )
            );
            least += almCore.bufferAmount0().fullMulDiv(shares, supply);
            // And: Where the shares hold no token0, a hole no bound expresses.
            vm.assume(least > 0);
            maxAssets = bound(maxAssets, 0, least - 1);
        }

        // When: The caller mints.
        // Then: It reverts on the bound.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.ExcessiveInput.selector);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);
    }

    function testFuzz_Revert_mint_ExcessiveInput_BelowTheCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxAssets,
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

        // And: At most maxMint, and a funded caller.
        uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(ceiling > 0);
        shares = bound(shares, 1, ceiling);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // And: A bound below what the shares are worth at spot, rounded down.
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            (uint256 value0, uint256 value1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                uint128(
                    (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
                    .fullMulDiv(shares, supply)
                )
            );
            value0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
            value1 += almCore.bufferAmount1().fullMulDiv(shares, supply);
            uint256 least = isToken0
                ? value0 + token1ToToken0(sqrtPriceX96(pool), value1)
                : value1 + token0ToToken1(sqrtPriceX96(pool), value0);
            // And: Where the shares are worth under a wei, a hole no bound expresses.
            vm.assume(least > 0);
            maxAssets = bound(maxAssets, 0, least - 1);
        }

        // When: The caller mints.
        // Then: It reverts on the bound.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.ExcessiveInput.selector);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);
    }

    function testFuzz_Revert_mint_ExcessiveInput_BothTokensUnderQuoted(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A token0 vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot below the range, so the range holds token0 only.
        parkAtTick(pool, users.unprivilegedAddress, range.tickLower - poolState.tickSpacing);
        vm.warp(vm.getBlockTimestamp() + 2 * Constants.TWAP_WINDOW);

        // And: A buffer holding the range's token0 and a token1 per share on top.
        uint256 supply = almCore.totalSupply();
        {
            Range memory staged = almCore.getRange(0);
            (uint256 held,) = amountsRoundedUp(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            fundBuffer(held, supply);

            // And: A buffer the mint cannot push past a uint128.
            vm.assume(almCore.bufferAmount0() <= Constants.MAX_FUZZED_AMOUNT);

            // And: At most maxMint and half an amount's worth of token0.
            (uint256 fees0,,) = almCore.getUnstakedPositions();
            uint256 ceiling = FixedPointMathLib.min(
                IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress),
                (Constants.MAX_FUZZED_AMOUNT / 2).fullMulDiv(supply, held + fees0 + almCore.bufferAmount0())
            );
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(shares, 1, ceiling);
        }

        // And: A funded caller, the vault holding both tokens to pay a dearer mint.
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        token0.mint(address(vault), Constants.MAX_FUZZED_AMOUNT);
        token1.mint(address(vault), Constants.MAX_FUZZED_AMOUNT);

        // And: The vault reading an empty buffer, quoting less than the mint takes.
        vm.mockCall(
            address(almCore),
            abi.encodeWithSignature("extsload(bytes32)", bytes32(uint256(STATE_SLOT) + ALMCoreViewLogic.BUFFER_OFFSET)),
            abi.encode(bytes32(0))
        );

        // When: The caller mints with no bound of its own.
        // Then: It reverts, the mint taking more than the vault bought and pulled.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.ExcessiveInput.selector);
        vault.mint(shares, users.unprivilegedAddress, type(uint256).max);
    }

    function testFuzz_Revert_mint_InsufficientOutput_BeyondTheSwapCost(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A max swap cost up to 10 bps above the pool's fee.
        maxSwapCostBps = bound(maxSwapCostBps, poolState.fee / 100 + 1, poolState.fee / 100 + 10);

        // And: A seeded vault holding a range, under that cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        givenValidCoreStateAboveTheRounding(
            coreState, poolState, range, isToken0, maxSwapCostBps * 100 - poolState.fee, 0
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(maxSwapCostBps);

        // And: A mint of over twice maxMint, in the room and half depth.
        {
            uint256 floor = 2 * IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress) + 1;
            uint256 ceiling = FixedPointMathLib.min(
                almCore.totalCap_() - almCore.totalSupply(), mintableWithinDepth(isToken0, poolState.liquidityPool)
            );
            // And: Where the room is under twice maxMint, a hole no bound expresses.
            vm.assume(floor <= ceiling);
            shares = bound(shares, floor, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // When: The caller mints through the plain signature.
        // Then: It reverts, the swap stopping at the band's edge short of the need.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(ALMVaultSync.InsufficientOutput.selector);
        vault.mint(shares, users.unprivilegedAddress);
    }

    function testFuzz_Revert_mint_SPL_TheSwapCostIsWithinTheFee(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);

        // And: A swap fee of 0.01% to the most the factory accepts.
        poolState.fee = uint24(bound(poolState.fee, 100, Constants.MAX_POOL_FEE));
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

        // And: A mint that buys the non-asset, within half depth, and a funded caller.
        {
            uint256 ceiling = mintableWithinDepth(isToken0, poolState.liquidityPool);
            // And: Where half the depth buys under a share, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(shares, 1, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // When: The caller mints through the plain signature.
        // Then: It reverts in the pool, the swap's limit being spot.
        vm.prank(users.unprivilegedAddress);
        vm.expectRevert(bytes("SPL"));
        vault.mint(shares, users.unprivilegedAddress);
    }

    function testFuzz_Success_mint_ZeroTakesNothing(
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
        uint256 supplyBefore = almCore.totalSupply();

        // When: The caller mints nothing through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(0, users.unprivilegedAddress);

        // Then: Nothing was paid or minted.
        assertEq(assets, 0);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), 0);
        assertEq(almCore.totalSupply(), supplyBefore);
    }

    function testFuzz_Success_mint_TheHeadroom(
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
        uint256 maxAssets = type(uint128).max;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), maxAssets, address(vault));

        // When: The receiver mints what maxMint reports.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);

        // Then: It is the room, and its cap balance sits at the per user cap.
        assertEq(shares, room);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), room);
        assertEq(room + almCore.pendingShares_(users.unprivilegedAddress), almCore.perUserCap_());
    }

    function testFuzz_Success_mint_MaxMintAtTheTotalCap(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
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

        // And: A total cap that leaves a fuzzed room above the supply, within maxMint.
        uint256 stepRoom = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(stepRoom > 0);
        room = bound(room, 1, stepRoom);
        uint256 totalCap = almCore.totalSupply() + room;
        vm.prank(factory);
        almCore.setTotalCap(totalCap);
        uint256 maxAssets = type(uint128).max;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), maxAssets, address(vault));

        // When: The caller mints what maxMint reports.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);

        // Then: It was the room, and the supply sits at the total cap.
        assertEq(shares, room);
        assertEq(almCore.totalSupply(), almCore.totalCap_());
    }

    function testFuzz_Success_mint_MaxMintThroughThePlainSignature(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 room,
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

        // And: A total cap room that fits the buffers, the token deltas and the ticks.
        {
            uint256 supply = almCore.totalSupply();
            uint256 most = type(uint128).max - supply;
            uint256 buffer = FixedPointMathLib.max(almCore.bufferAmount0(), almCore.bufferAmount1());
            if (buffer > 0) {
                most = FixedPointMathLib.min(most, supply.fullMulDiv(type(uint128).max - 1 - buffer, buffer));
            }
            uint256 liquidity =
                uint256(positionLiquidity(almCore.getRange(0).unstakedTokenId)) + almCore.getRange(0).stakedLiquidity;
            if (liquidity > 0) {
                uint256 maxPerTick = tickSpacingToMaxLiquidityPerTick(poolState.tickSpacing);
                most = FixedPointMathLib.min(most, supply.fullMulDiv(maxPerTick - 1 - liquidity, liquidity));
                (uint256 amount0,) = amountsRoundedUp(
                    TickMath.MIN_SQRT_PRICE,
                    almCore.getRange(0).tickLower,
                    almCore.getRange(0).tickUpper,
                    uint128(liquidity)
                );
                (, uint256 amount1) = amountsRoundedUp(
                    TickMath.MAX_SQRT_PRICE - 1,
                    almCore.getRange(0).tickLower,
                    almCore.getRange(0).tickUpper,
                    uint128(liquidity)
                );
                buffer = FixedPointMathLib.max(amount0 + almCore.bufferAmount0(), amount1 + almCore.bufferAmount1());
            }
            if (buffer > 0) {
                most = FixedPointMathLib.min(most, supply.fullMulDiv(Constants.MAX_FUZZED_AMOUNT - 2, buffer));
            }
            // And: Where no share fits the amounts, a hole no bound expresses.
            vm.assume(most > 0);
            room = bound(room, 1, most);
        }
        uint256 totalCap = almCore.totalSupply() + room;
        vm.prank(factory);
        almCore.setTotalCap(totalCap);

        // And: A caller funded with what a signed 128-bit amount holds.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), Constants.MAX_FUZZED_AMOUNT, address(vault));

        // When: The caller mints maxMint through the plain signature.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);

        // Then: It minted the whole room.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_mint_MaxMintOfATinyRoom(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 room,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A per user cap room of 1 to 100 shares.
        vm.prank(factory);
        almCore.setPerUserCap(bound(room, 1, 100));

        // And: A max swap cost above the pool's fee and below the whole value.
        maxSwapCostBps = bound(maxSwapCostBps, poolState.fee / 100 + 1, ConfigLib.BPS_DENOMINATOR - 1);
        setMaxSwapCost(maxSwapCostBps);

        // And: The most the caller may mint, and a caller funded far above what it costs.
        uint256 shares = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // When: The caller mints it through the plain signature.
        if (shares > 0) {
            vm.prank(users.unprivilegedAddress);
            vault.mint(shares, users.unprivilegedAddress);
        }

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_mint_MaxAssetsEqualToTheAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // And: At most maxMint, a funded caller, and the assets its mint pays.
        uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(ceiling > 0);
        shares = bound(shares, 1, ceiling);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        uint256 snapshot = vm.snapshotState();
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(shares, users.unprivilegedAddress, type(uint256).max);
        vm.revertToState(snapshot);

        // When: The caller mints with a bound of exactly those assets.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, assets);

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_mint_RefundsOnlyInTheAsset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
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

        // And: At most maxMint, and a caller funded far above what it costs.
        uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(ceiling > 0);
        shares = bound(shares, 1, ceiling);
        uint256 maxAssets = type(uint128).max;
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), maxAssets, address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, maxAssets);

        // Then: The caller holds the shares, and none of the non-asset came back.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertEq((isToken0 ? token1 : token0).balanceOf(users.unprivilegedAddress), 0);
    }

    function testFuzz_Success_mint_PaysWhatThePoolAndTheCoreTook(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, in a pool charging a fuzzed swap fee.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: At most maxMint, and a funded caller.
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(shares, 1, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        ERC20Mock asset = ERC20Mock(vault.asset());
        uint256 held = asset.balanceOf(address(pool)) + asset.balanceOf(address(almCore));

        // And: What the shares' part of the holdings is worth at spot, rounded down.
        uint256 least;
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            (uint256 value0, uint256 value1) = amountsRoundedDown(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                uint128(
                    (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
                    .fullMulDiv(shares, supply)
                )
            );
            value0 += almCore.bufferAmount0().fullMulDiv(shares, supply);
            value1 += almCore.bufferAmount1().fullMulDiv(shares, supply);
            least = isToken0
                ? value0 + token1ToToken0(sqrtPriceX96(pool), value1)
                : value1 + token0ToToken1(sqrtPriceX96(pool), value0);
        }

        // When: The caller mints with no bound of its own.
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(shares, users.unprivilegedAddress, type(uint256).max);

        // Then: The caller holds the shares and got back what it did not pay.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertEq(asset.balanceOf(users.unprivilegedAddress), type(uint128).max - assets);

        // And: It paid what the pool and the core took, and the vault kept none of it.
        assertEq(assets, asset.balanceOf(address(pool)) + asset.balanceOf(address(almCore)) - held);
        assertEq(asset.balanceOf(address(vault)), 0);

        // And: It paid at least what the shares are worth at spot.
        assertGe(assets, least);
    }

    function testFuzz_Success_mint_RefundsMoreThanItPaid(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A range around spot.
        givenValidRangeState(range, poolState, true);

        // And: A token0 vault seeded with it.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: Spot below the range and no token1 buffer, so a mint costs token0 only.
        parkAtTick(pool, users.unprivilegedAddress, range.tickLower - poolState.tickSpacing);
        vm.warp(vm.getBlockTimestamp() + 2 * Constants.TWAP_WINDOW);
        almCore.setBuffers(almCore.bufferAmount0(), 0);

        // And: An eighth of the supply to maxMint, at most a sixteenth of an amount.
        uint256 supply = almCore.totalSupply();
        {
            Range memory staged = almCore.getRange(0);
            (uint256 held,) = amountsRoundedUp(
                sqrtPriceX96(pool),
                staged.tickLower,
                staged.tickUpper,
                positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
            );
            (uint256 fees0,,) = almCore.getUnstakedPositions();
            uint256 ceiling = FixedPointMathLib.min(
                IALMSyncExtension(address(vault)).maxMint(accountA),
                (Constants.MAX_FUZZED_AMOUNT / (2 * Constants.MOCKED_SUPPLY_DIVISOR))
                .fullMulDiv(supply, held + fees0 + almCore.bufferAmount0())
            );
            uint256 floor = FixedPointMathLib.max(supply / Constants.MOCKED_SUPPLY_DIVISOR, 1);
            // And: Where maxMint is under an eighth of the supply, a hole.
            vm.assume(ceiling >= floor);
            shares = bound(shares, floor, ceiling);
        }
        fundVaultCaller(accountA, vault.asset(), type(uint128).max, address(vault));

        // And: The vault reading an eighth of the supply, pulling about eight times more.
        vm.mockCall(
            address(almCore),
            abi.encodeWithSignature("totalSupply()"),
            abi.encode(supply / Constants.MOCKED_SUPPLY_DIVISOR)
        );

        // When: The caller mints with no bound of its own.
        vm.prank(accountA);
        uint256 assets = vault.mint(shares, accountA, type(uint256).max);

        // Then: The caller holds the shares and got back all it did not pay.
        assertEq(almCore.balanceOf(accountA), shares);
        assertEq(token0.balanceOf(accountA), type(uint128).max - assets);
        assertEq(token0.balanceOf(address(vault)), 0);
    }

    function testFuzz_Success_mint_PaysThePreviewWithADonatedPosition(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 donation,
        uint256 shares,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, in a pool charging a fuzzed swap fee.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: A third party adds liquidity to the core's unstaked position.
        donateToRange(range, uint128(bound(donation, 1, range.liquidity)));

        // And: At most a hundredth of the supply, and at most maxMint.
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(accountA);
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(
                shares, 1, FixedPointMathLib.min(ceiling, almCore.totalSupply() / Constants.MINT_SUPPLY_DIVISOR + 1)
            );
        }

        // And: A caller funded with exactly the preview.
        uint256 quoted = vault.previewMint(shares);
        fundVaultCaller(accountA, vault.asset(), quoted, address(vault));

        // When: The caller mints, bounded by the preview.
        vm.prank(accountA);
        uint256 assets = vault.mint(shares, accountA, quoted);

        // Then: The caller holds the shares and got back what it did not pay.
        assertEq(almCore.balanceOf(accountA), shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(accountA), quoted - assets);
    }

    function testFuzz_Success_mint_KeepsAFewWeiOfTheNonAsset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 amountIn,
        uint16 feeBps,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A fuzzed protocol share of the swap fees.
        feeBps = uint16(bound(feeBps, 0, almCore.MAX_FEE_BPS_()));
        vm.prank(factory);
        almCore.setProtocolFees(0, feeBps, users.feeRecipient);

        // And: A seeded vault under a fuzzed max swap cost.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        maxSwapCostBps = givenValidMaxSwapCost(maxSwapCostBps, poolState.fee);
        ALMVaultSync vault = vaultFor(isToken0);
        {
            (uint128 liquidity, uint128 liquidityStaked) = (range.liquidity, range.liquidityStaked);
            uint256 snapshot = vm.snapshotState();
            seededVault(coreState, range, isToken0);
            setMaxSwapCost(maxSwapCostBps);

            // And: A fee-earning trade that keeps spot inside the TWAP band.
            {
                uint256 most = feeEarningTrade(pool, range.liquidity, type(uint256).max, true);
                {
                    (uint256 bandLower,) = CLMath.getBand(almCore.meanSqrtPriceX96_(), almCore.maxSpotFromTwap_());
                    uint256 dryRun = vm.snapshotState();
                    token0.mint(accountA, most + 1);
                    swapAsActor(pool, accountA, address(token0), address(token1), most + 1, uint160(bandLower - 1));
                    most -= token0.balanceOf(accountA);
                    vm.revertToState(dryRun);
                }
                uint256 least = feeEarningTrade(pool, range.liquidity, 0, true);
                // And: Room for a fee-earning trade, a hole no bound expresses.
                vm.assume(least <= most);
                amountIn = bound(amountIn, least, most);
            }
            swapInPool(pool, users.liquidityProvider, address(token0), address(token1), amountIn);

            // And: The supply at its ceiling where the fuzzed one leaves maxMint zero.
            if (IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress) == 0) {
                vm.revertToState(snapshot);
                (range.liquidity, range.liquidityStaked) = (liquidity, liquidityStaked);
                coreState.supply = type(uint256).max;
                givenValidCoreState(coreState, poolState, range, 0, 0, 0);
                seededVault(coreState, range, isToken0);
                setMaxSwapCost(maxSwapCostBps);
                swapInPool(pool, users.liquidityProvider, address(token0), address(token1), amountIn);
            }
        }

        // And: At most a hundredth of the supply and maxMint, and a funded caller.
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(
                shares, 1, FixedPointMathLib.min(ceiling, almCore.totalSupply() / Constants.MINT_SUPPLY_DIVISOR + 1)
            );
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // And: The non-asset the shares cost at spot, rounded up.
        uint256 cost;
        {
            Range memory staged = almCore.getRange(0);
            uint256 supply = almCore.totalSupply();
            uint256 owed = (uint256(positionLiquidity(staged.unstakedTokenId)) + staged.stakedLiquidity)
            .fullMulDivUp(shares, supply);
            (uint256 cost0, uint256 cost1) =
                amountsRoundedUp(sqrtPriceX96(pool), staged.tickLower, staged.tickUpper, uint128(owed));
            (uint256 fees0, uint256 fees1) = positionFees(pool, staged.unstakedTokenId);
            cost0 += (almCore.bufferAmount0() + fees0 - fees0.fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR))
            .fullMulDivUp(shares, supply);
            cost1 += (almCore.bufferAmount1() + fees1 - fees1.fullMulDiv(feeBps, ConfigLib.BPS_DENOMINATOR))
            .fullMulDivUp(shares, supply);
            cost = isToken0 ? cost1 : cost0;
        }

        // And: The rounding the vault may keep of the non-asset with one range.
        uint256 tolerance;
        {
            uint256 liquidity = pool.liquidity();
            uint256 added = shares.fullMulDiv(
                uint256(positionLiquidity(almCore.getRange(0).unstakedTokenId)) + almCore.getRange(0).stakedLiquidity,
                almCore.totalSupply()
            );
            uint256 unit = 1 << 96;
            uint256 bought = cost + 2;
            tolerance = 3;
            if (!isToken0) {
                unit = uint256(sqrtPriceX96(pool)).fullMulDiv(sqrtPriceX96(pool), 1 << 96);
                bought += cost.divUp(unit) + 1;
                tolerance += 2 * cost.divUp(unit) + bought.divUp(unit) + 1;
            }
            tolerance += (added + 2 * bought).divUp(liquidity) + (added + 2).divUp(unit);
        }
        ERC20Mock nonAsset = isToken0 ? token1 : token0;
        uint256 balance = nonAsset.balanceOf(address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, type(uint128).max);

        // Then: The caller holds the shares, the vault at most that rounding.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertLe(nonAsset.balanceOf(address(vault)) - balance, tolerance);
    }

    function testFuzz_Success_mint_Token0_BuysExactlyTheToken1ACoreOfBuffersTakes(
        PoolState memory poolState,
        CoreState memory coreState,
        uint256 shares,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A token0 vault whose core holds only buffers, no range.
        RangeState memory none;
        givenValidCoreState(coreState, poolState, none, 0, 0, 0);
        setCoreState(coreState);
        ALMVaultSync vault = vaultFor(true);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: At most maxMint and half the supply, and a funded caller.
        uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
        // And: Where maxMint is zero, a hole no bound expresses.
        vm.assume(ceiling > 0);
        shares = bound(shares, 1, FixedPointMathLib.min(ceiling, almCore.totalSupply() / 2 + 1));
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));
        uint256 balance = token1.balanceOf(address(vault));

        // When: The caller mints.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, type(uint128).max);

        // Then: The caller holds the shares, the vault none of the token1 it bought.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertEq(token1.balanceOf(address(vault)), balance);
    }

    function testFuzz_Success_mint_BuysPastATickWithMoreLiquidity(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 extra,
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

        // And: Another position from the next spacing in the buy's direction.
        int24 edge;
        {
            {
                int24 tick = currentTick(pool);
                edge = tick / poolState.tickSpacing * poolState.tickSpacing;
                if (tick < 0 && tick % poolState.tickSpacing != 0) edge -= poolState.tickSpacing;
            }
            if (!isToken0) edge += poolState.tickSpacing;
            (int24 tickLower, int24 tickUpper) =
                isToken0 ? (edge - 10 * poolState.tickSpacing, edge) : (edge, edge + 10 * poolState.tickSpacing);
            uint256 room = tickSpacingToMaxLiquidityPerTick(poolState.tickSpacing) - pool.liquidity()
                - positionLiquidity(almCore.getRange(0).unstakedTokenId) - almCore.getRange(0).stakedLiquidity;
            extra = bound(extra, pool.liquidity(), room);
            (uint256 amount0, uint256 amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), tickLower, tickUpper, uint128(extra));
            mintPosition(pool, users.liquidityProvider, tickLower, tickUpper, amount0, amount1);
        }

        // And: A mint needing more than the pool sells to that tick, within the position.
        {
            uint256 sold = isToken0
                ? SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtPriceAtTick(edge), sqrtPriceX96(pool), pool.liquidity(), false
                )
                : SqrtPriceMath.getAmount0Delta(
                    sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(edge), pool.liquidity(), false
                );
            uint256 least;
            {
                Range memory staged = almCore.getRange(0);
                (uint256 edge0, uint256 edge1) = amountsRoundedDown(
                    TickMath.getSqrtPriceAtTick(edge),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                uint256 edgeOut = isToken0 ? edge1 + almCore.bufferAmount1() : edge0 + almCore.bufferAmount0();
                // And: Where the edge holds no non-asset, a hole no bound expresses.
                vm.assume(edgeOut > 0);
                least = sold.fullMulDiv(almCore.totalSupply(), edgeOut) + 1;
            }
            sold += isToken0
                ? SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtPriceAtTick(edge - 10 * poolState.tickSpacing),
                    TickMath.getSqrtPriceAtTick(edge),
                    pool.liquidity() + uint128(extra),
                    false
                )
                : SqrtPriceMath.getAmount0Delta(
                    TickMath.getSqrtPriceAtTick(edge),
                    TickMath.getSqrtPriceAtTick(edge + 10 * poolState.tickSpacing),
                    pool.liquidity() + uint128(extra),
                    false
                );
            uint256 need;
            {
                Range memory staged = almCore.getRange(0);
                (uint256 spot0, uint256 spot1) = amountsRoundedUp(
                    sqrtPriceX96(pool),
                    staged.tickLower,
                    staged.tickUpper,
                    positionLiquidity(staged.unstakedTokenId) + staged.stakedLiquidity
                );
                need = isToken0 ? spot1 + almCore.bufferAmount1() : spot0 + almCore.bufferAmount0();
            }
            uint256 most = FixedPointMathLib.min(
                sold.zeroFloorSub(
                        isToken0
                            ? uint256(sqrtPriceX96(pool)).divUp(1 << 96) + 3
                            : uint256(1 << 96).divUp(sqrtPriceX96(pool)) + 3
                    )
                    .fullMulDiv(almCore.totalSupply(), need),
                IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress)
            );
            // And: Room past the tick within the position, a hole no bound expresses.
            vm.assume(least <= most);
            shares = bound(shares, least, most);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // When: The caller mints through the plain signature.
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(shares, users.unprivilegedAddress);

        // Then: Its buy crossed the tick.
        if (isToken0) assertLt(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(edge));
        else assertGt(sqrtPriceX96(pool), TickMath.getSqrtPriceAtTick(edge));

        // And: It minted the shares, and the caller got back what it did not pay.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
        assertEq(ERC20Mock(vault.asset()).balanceOf(users.unprivilegedAddress), type(uint128).max - assets);
    }

    function testFuzz_Success_mint_MaxAssetsSkipsTheValueLossCheck(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);

        // And: A non-asset buffer worth twice a buy whose fee beats the rounding.
        uint256 leg = uint256(4e6).divUp(poolState.fee);
        leg = isToken0
            ? leg.fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192)
            : leg.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice);
        givenValidCoreState(
            coreState, poolState, range, coreState.supply, isToken0 ? 0 : 2 * leg + 4, isToken0 ? 2 * leg + 4 : 0
        );
        ALMVaultSync vault = seededVault(coreState, range, isToken0);

        // And: A mint whose buy's fee beats the rounding, in the room and half depth.
        {
            uint256 supply = almCore.totalSupply();
            uint256 floor = (leg + 1).fullMulDivUp(supply, isToken0 ? almCore.bufferAmount1() : almCore.bufferAmount0());
            uint256 ceiling = FixedPointMathLib.min(supply / 2, mintableWithinDepth(isToken0, poolState.liquidityPool));
            // And: Where the room is under the fee's floor, a hole no bound expresses.
            vm.assume(floor <= ceiling);
            shares = bound(shares, floor, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // And: A max swap cost of zero.
        setMaxSwapCost(0);

        // When: The caller mints with a bound of its own.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress, type(uint256).max);

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }

    function testFuzz_Success_mint_LeavesStrayTokensUntouched(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        uint256 strayAsset,
        uint256 strayOther,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a caller funded for a mint.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        {
            uint256 ceiling = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(ceiling > 0);
            shares = bound(shares, 1, ceiling);
        }
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), type(uint128).max, address(vault));

        // And: Stray asset and other pool token donated to the vault.
        ERC20Mock other = isToken0 ? token1 : token0;
        strayAsset = bound(strayAsset, 1, Constants.MAX_FUZZED_AMOUNT);
        strayOther = bound(strayOther, 1, Constants.MAX_FUZZED_AMOUNT);
        ERC20Mock(vault.asset()).mint(address(vault), strayAsset);
        other.mint(address(vault), strayOther);
        uint256 poolOther = other.balanceOf(address(pool));
        uint256 coreOther = other.balanceOf(address(almCore));

        // When: The caller mints through the plain signature.
        vm.prank(users.unprivilegedAddress);
        vault.mint(shares, users.unprivilegedAddress);

        // Then: The caller holds the shares.
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);

        // And: The vault still holds the stray tokens, beside the other token it kept.
        assertEq(ERC20Mock(vault.asset()).balanceOf(address(vault)), strayAsset);
        assertEq(
            other.balanceOf(address(vault)),
            strayOther + poolOther - other.balanceOf(address(pool)) - (other.balanceOf(address(almCore)) - coreOther)
        );
    }

    function testFuzz_Success_mint_PaysAtMostTheFeeOverTheSharesWorthWithADustAssetLeg(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 leg,
        uint256 shares,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault, token1 in a range below spot, a token0 buffer of a leg.
        leg = bound(leg, 0, Constants.MAX_FUZZED_AMOUNT / 4);
        ALMVaultSync vault = seededThinLegVault(poolState, coreState, range, true, leg, maxSwapCostBps);

        // And: Shares up to a nonzero maxMint, and a caller funded with their quote.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(most > 0);
            shares = bound(shares, 1, most);
        }
        fundVaultCaller(
            users.unprivilegedAddress,
            address(token0),
            IALMSyncExtension(address(vault)).previewMint(shares),
            address(vault)
        );

        // When: The caller mints them.
        vm.recordLogs();
        vm.prank(users.unprivilegedAddress);
        uint256 paid = vault.mint(shares, users.unprivilegedAddress);

        // Then: It paid at most the fee on the swap's input and each leg's rounding over the shares' worth.
        (uint256 swapIn,) = swapAmounts(address(vault));
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 liquidity = pool.liquidity();
        uint256 rounding = uint256(1 << 96).divUp(sqrtPrice) + 3
            + liquidity.fullMulDivUp(1 << 96, sqrtPrice).divUp(sqrtPrice)
            + (sqrtPrice.divUp(1 << 96) + 3 + liquidity.divUp(1 << 96)).fullMulDivUp(1 << 192, sqrtPrice * sqrtPrice);
        assertLe(
            paid,
            holdingsValue(true).fullMulDiv(shares, almCore.totalSupply()) + swapIn.fullMulDivUp(pool.fee(), 1e6)
                + rounding
        );
    }

    function testFuzz_Success_mint_FillsBesideTheRangeEdgeWithoutIdleNonAsset(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 gap,
        uint256 shares,
        uint256 maxSwapCostBps,
        bool isToken0
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A vault seeded with a range around spot, its non-asset buffer taken out.
        givenValidRangeState(range, poolState, true);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        ERC20Mock other = isToken0 ? token1 : token0;
        {
            uint256 held = isToken0 ? almCore.bufferAmount1() : almCore.bufferAmount0();
            almCore.setBuffers(isToken0 ? almCore.bufferAmount0() : 0, isToken0 ? 0 : almCore.bufferAmount1());
            deal(address(other), address(almCore), other.balanceOf(address(almCore)) - held);
        }

        // And: A trade to beside the range's edge, under a wei of the non-asset from it.
        uint160 edge = TickMath.getSqrtPriceAtTick(isToken0 ? range.tickLower : range.tickUpper);
        {
            uint128 liquidity = pool.liquidity();
            uint256 most = isToken0
                ? ((1 << 96) - 1) / liquidity
                : (uint256(edge) * edge - 1) / ((uint256(liquidity) << 96) + edge);
            // And: A step selling under a wei, a hole of liquidity over the edge's price.
            vm.assume(most > 0);
            gap = bound(gap, 1, most);
            uint160 target = uint160(isToken0 ? edge + gap : edge - gap);
            parkSpotAt(target, liquidity, pool.fee());
            assertEq(sqrtPriceX96(pool), target);
        }

        // And: No fees of the non-asset on the core's position.
        {
            (uint256 fees0, uint256 fees1,) = almCore.getUnstakedPositions();
            assertEq(isToken0 ? fees1 : fees0, 0);
        }

        // And: Shares up to a nonzero maxMint, and a caller funded with their quote.
        {
            uint256 most = IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress);
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(most > 0);
            shares = bound(shares, 1, most);
        }
        uint256 quote = IALMSyncExtension(address(vault)).previewMint(shares);
        fundVaultCaller(users.unprivilegedAddress, vault.asset(), quote, address(vault));

        // When: The caller mints them.
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(shares, users.unprivilegedAddress);

        // Then: It minted the shares for at most the quote.
        assertLe(assets, quote);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);

        // And: The buy moved spot past the edge with a wei of the non-asset, kept.
        assertEq(other.balanceOf(address(vault)), 1);
        if (isToken0) assertLt(sqrtPriceX96(pool), edge);
        else assertGt(sqrtPriceX96(pool), edge);
    }

    function testFuzz_Success_mint_FillsAtTheQuoteWhenTheBuyCarriesAFeeWei(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 trade,
        uint256 shares,
        uint256 protocolSwapFeeBps,
        uint256 maxSwapCostBps
    ) public {
        // Given: A token0 vault with a range around spot, the protocol taking swap fees.
        ALMVaultSync vault = seededFeeCarryVault(poolState, coreState, range, protocolSwapFeeBps, maxSwapCostBps);
        roundTrip(true, trade);
        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);

        // And: The quote of a mint up to the supply and a nonzero maxMint, funded.
        {
            uint256 most = FixedPointMathLib.min(
                almCore.totalSupply(), IALMSyncExtension(address(vault)).maxMint(users.unprivilegedAddress)
            );
            // And: Where maxMint is zero, a hole no bound expresses.
            vm.assume(most > 0);
            shares = bound(shares, 1, most);
        }
        uint256 quote = IALMSyncExtension(address(vault)).previewMint(shares);
        fundVaultCaller(users.unprivilegedAddress, address(token0), quote, address(vault));
        uint256 balance = token0.balanceOf(users.unprivilegedAddress);

        // When: The caller mints the shares with the quote as its maximum.
        vm.prank(users.unprivilegedAddress);
        uint256 assets = vault.mint(shares, users.unprivilegedAddress, quote);

        // Then: It paid at most the quote, and what it took.
        assertLe(assets, quote);
        assertEq(balance - token0.balanceOf(users.unprivilegedAddress), assets);
        assertEq(almCore.balanceOf(users.unprivilegedAddress), shares);
    }
}

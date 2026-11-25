/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreExtension } from "../../utils/extensions/ALMCoreExtension.sol";
import { ALMCoreViewLogicExtension } from "../../utils/extensions/ALMCoreViewLogicExtension.sol";
import { ALMFactoryExtension } from "../../utils/extensions/ALMFactoryExtension.sol";
import { ALMFixture } from "../../utils/fixtures/alm/ALMFixture.f.sol";
import { ALMKeeperExtension } from "../../../src/core/ALMKeeperExtension.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { CalldataLogic } from "../../../src/core/libraries/logic/CalldataLogic.sol";
import { ConfigLib } from "../../../src/core/libraries/state/ConfigLib.sol";
import { Constants } from "../../utils/Constants.sol";
import { ERC20Mock } from "../../utils/mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { Fuzz_Test } from "../Fuzz.t.sol";
import { ICLGauge } from "../../utils/fixtures/metadex/interfaces/ICLGauge.sol";
import { ICLPool } from "../../utils/fixtures/metadex/interfaces/ICLPool.sol";
import { INonfungiblePositionManager } from "../../utils/fixtures/metadex/interfaces/INonfungiblePositionManager.sol";
import { LockProbeRouterMock } from "../../utils/mocks/LockProbeRouterMock.sol";
import { Plan } from "../../utils/Plan.sol";
import { Range } from "../../../src/core/types/Range.sol";
import { RouterTrampoline } from "../../utils/fixtures/asset-managers/RouterTrampoline.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { Sentinels } from "../../../src/core/libraries/Sentinels.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { StdStorage, stdStorage } from "@forge-std/Test.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Common logic needed by all "ALMCore" fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract ALMCore_Fuzz_Test is Fuzz_Test, ALMFixture {
    using FixedPointMathLib for uint256;
    using Plan for Plan.Steps;
    using stdStorage for StdStorage;

    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    struct PoolState {
        uint256 sqrtPrice;
        uint128 liquidityPool;
        uint24 fee;
        uint24 unstakedFee;
        uint8 decimals0;
        uint8 rewardPoolToken;
        int24 tickCurrent;
        int24 tickSpacing;
    }

    struct CoreState {
        uint256 supply;
        uint256 buffer0;
        uint256 buffer1;
    }

    struct ConfigState {
        uint256 totalCap;
        uint256 perUserCap;
        uint256 maxDeviation;
        uint16 maxShortfallBps;
        uint16 maxSwapCostBps;
        uint16 protocolEmissionFeeBps;
        uint16 protocolSwapFeeBps;
        bool paused;
    }

    struct QueueState {
        uint256 deposit0;
        uint256 deposit1;
        uint256 redeem0;
        uint256 redeem1;
    }

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    // The factory every core checks its privileged callers against.
    address internal factory;
    // The controllers queue tests record requests for.
    address internal controller = makeAddr("controller");
    address internal secondController = makeAddr("secondController");
    // The asynchronous vaults of the core, the only callers its queue accepts.
    address internal asyncVault0;
    address internal asyncVault1;
    // The aLP holders reward and transfer tests move shares between.
    address internal accountA = makeAddr("accountA");
    address internal accountB = makeAddr("accountB");
    address internal accountC = makeAddr("accountC");
    // The holder of the dead shares.
    address internal deadAddress = address(1);

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ALMFactoryExtension internal deployer;
    ALMCoreExtension internal almCore;
    ICLGauge internal gauge;
    ICLPool internal pool;
    RouterTrampoline internal routerTrampoline;
    ALMCoreViewLogicExtension internal coreViewLogic;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override(Fuzz_Test) {
        Fuzz_Test.setUp();
        coreViewLogic = new ALMCoreViewLogicExtension();
    }

    function deployStack(bool root, PoolState memory poolState) internal virtual {
        deployMetadex(root);
        deployMetadexCL();

        if (poolState.rewardPoolToken == 0) {
            deployCodeTo("ERC20Mock.sol:ERC20Mock", abi.encode("Token 0", "TKN0", poolState.decimals0), address(token0));
            deployCodeTo(
                "ERC20Mock.sol:ERC20Mock",
                abi.encode("Token 1", "TKN1", poolState.decimals0 == 18 ? 6 : 18),
                address(token1)
            );
        } else {
            vm.etch(rewardToken, address(new ERC20Mock("Reward Token", "RWRD", 18)).code);
            address other =
                poolState.rewardPoolToken == 1 ? address(uint160(rewardToken) + 1) : address(uint160(rewardToken) - 1);
            deployCodeTo("ERC20Mock.sol:ERC20Mock", abi.encode("Token B", "TKNB", uint8(6)), other);
            (token0, token1) = poolState.rewardPoolToken == 1
                ? (ERC20Mock(rewardToken), ERC20Mock(other))
                : (ERC20Mock(other), ERC20Mock(rewardToken));
        }

        pool = createPool(
            address(token0),
            address(token1),
            poolState.tickSpacing,
            uint160(poolState.sqrtPrice),
            OBSERVATION_CARDINALITY
        );
        gauge = createGauge(pool, true);
    }

    function deployCore() internal virtual {
        routerTrampoline = new RouterTrampoline();
        deployer = deployFactory(extensionCreationCodes(), address(routerTrampoline), users.owner, users.steward);
        factory = address(deployer);

        almCore = ALMCoreExtension(
            createInThreeTransactions(
                deployer, address(pool), extensionCreationCodes(), users.steward, users.feeRecipient
            )
        );
        Vaults memory vaults_ = deployer.getVaults(address(almCore));
        (asyncVault0, asyncVault1) = (vaults_.asyncVault0, vaults_.asyncVault1);
        vm.label(address(almCore), "ALMCore");
        vm.label(address(deployer), "ALMFactory");
    }

    /* //////////////////////////////////////////////////////////////
                               POOL STATE
    ////////////////////////////////////////////////////////////// */

    function givenValidPoolState(PoolState memory poolState) internal pure {
        // And: A tick spacing the factory enables that divides the fixture's.
        int24[4] memory tickSpacings = [TICK_SPACING, TICK_SPACING / 2, TICK_SPACING / 4, int24(1)];
        poolState.tickSpacing = tickSpacings[bound(uint256(int256(poolState.tickSpacing)), 0, 3)];

        // And: A swap fee and an unstaked fee the factory accepts.
        poolState.fee = uint24(bound(poolState.fee, 1, Constants.MAX_POOL_FEE));
        poolState.unstakedFee = uint24(bound(poolState.unstakedFee, 0, Constants.MAX_UNSTAKED_FEE));

        // And: Either token order of the fixture's two decimal sets.
        poolState.decimals0 = bound(poolState.decimals0, 0, 1) == 0 ? 18 : 6;

        // And: A reward token that is not one of the pool's tokens.
        poolState.rewardPoolToken = 0;

        // And: A price inside the band the amount math covers, clear of its ends.
        int24 tickUpper = bandTick(poolState.tickSpacing);
        poolState.sqrtPrice = bound(
            poolState.sqrtPrice,
            uint256(TickMath.getSqrtPriceAtTick(-tickUpper)) * 1e3,
            Constants.BOUND_SQRT_PRICE_UPPER / 1e3
        );

        // And: Other providers' depth within a tick's limit and an eighth of an amount.
        uint128 depth = tickSpacingToMaxLiquidityPerTick(poolState.tickSpacing) / 10;
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(uint160(poolState.sqrtPrice), -tickUpper, tickUpper, depth);
        uint256 worth = amount0 > amount1 ? amount0 : amount1;
        if (worth > Constants.MAX_FUZZED_AMOUNT / 8) {
            depth = uint128(uint256(depth).fullMulDiv(Constants.MAX_FUZZED_AMOUNT / 8, worth));
        }
        poolState.liquidityPool = uint128(bound(poolState.liquidityPool, depth / 100, depth));
    }

    function givenSpacingRoom(PoolState memory poolState) internal pure {
        // And: A price in the middle half of its tick spacing.
        int24 tickSpacing = poolState.tickSpacing;
        int24 tick = TickMath.getTickAtSqrtPrice(uint160(poolState.sqrtPrice));
        int24 tickBelow = tick - (tick % tickSpacing + tickSpacing) % tickSpacing;
        uint256 lower = TickMath.getSqrtPriceAtTick(tickBelow);
        uint256 quarter = (TickMath.getSqrtPriceAtTick(tickBelow + tickSpacing) - lower) / 4;
        poolState.sqrtPrice = bound(poolState.sqrtPrice, lower + quarter, lower + 3 * quarter);
    }

    function setPoolState(PoolState memory poolState, bool root) internal {
        deployStack(root, poolState);
        stdstore.target(address(CL_FACTORY))
            .sig("tickSpacingToFee(int24)")
            .with_key(uint256(int256(poolState.tickSpacing)))
            .checked_write(poolState.fee);
        CL_FACTORY.setDefaultUnstakedFee(poolState.unstakedFee);

        deployCore();
        deployer.setIsKeeper(address(almCore), users.keeper, true);
        vm.startPrank(factory);
        almCore.setPlanLimits(0, 0, 0);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, Constants.WIDE_DEVIATION, Constants.WIDE_DEVIATION, Constants.OPEN_TWAP_DEVIATION
        );
        almCore.setRangeCap(ConfigLib.MAX_RANGE_CAP);
        vm.stopPrank();

        int24 tickUpper = bandTick(poolState.tickSpacing);
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), -tickUpper, tickUpper, poolState.liquidityPool);
        mintPosition(pool, users.liquidityProvider, -tickUpper, tickUpper, amount0, amount1);

        vm.warp(vm.getBlockTimestamp() + Constants.TWAP_WINDOW);
        poolState.sqrtPrice = sqrtPriceX96(pool);
        almCore.setLastExchangeRate(1, uint160(poolState.sqrtPrice));
        poolState.tickCurrent = currentTick(pool);
        poolState.liquidityPool = pool.liquidity();
        poolState.fee = pool.fee();
        poolState.unstakedFee = pool.unstakedFee();
    }

    function setSpotPoolState() internal returns (PoolState memory poolState) {
        // And: A pool at price 1 with a 0.05% fee and liquidity 1e25.
        poolState.sqrtPrice = 1 << 96;
        poolState.fee = 500;
        givenValidPoolState(poolState);
        poolState.liquidityPool = 1e25;
        setPoolState(poolState, false);
    }

    /* //////////////////////////////////////////////////////////////
                               CORE STATE
    ////////////////////////////////////////////////////////////// */

    function givenValidCoreState(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range,
        uint256 least,
        uint256 least0,
        uint256 least1
    ) internal view {
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(
            sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
        );

        // And: A buffer from its floor to all the range holds over it, some for the seed.
        coreState.buffer0 = bound(
            coreState.buffer0,
            amount0 + FixedPointMathLib.max(least0, amount0 > 0 ? 0 : 1),
            amount0 + least0 + (amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4)
        );
        coreState.buffer1 = bound(
            coreState.buffer1,
            amount1 + FixedPointMathLib.max(least1, amount1 > 0 ? 0 : 1),
            amount1 + least1 + (amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4)
        );

        // And: A supply from its floor and the dead shares up to the vault's own value.
        uint256 floor = FixedPointMathLib.max(least, almCore.DEAD_SHARES_());
        uint256 ceiling = FixedPointMathLib.min(
            coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0), Constants.MAX_FUZZED_AMOUNT
        );
        coreState.supply = bound(coreState.supply, floor, FixedPointMathLib.max(ceiling, floor));
    }

    function givenShareWorthMoreThanToken0(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range
    ) internal view {
        // And: Buffers whose dead shares are each worth more than a token0 wei.
        uint256 price = poolState.sqrtPrice * poolState.sqrtPrice >> 192;
        uint256 least = price * Constants.DEAD_SHARES + 1;
        uint256 ceiling0;
        uint256 ceiling1;
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            ceiling0 = amount0 + (amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4);
            ceiling1 =
                amount1 + FixedPointMathLib.max(amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4, least + 1);
        }
        {
            (uint256 top0, uint256 top1,,) = stagedAmounts(poolState, range, ceiling0, ceiling1);
            uint256 needed = FixedPointMathLib.fullMulDivUp(
                least.zeroFloorSub(top1), 1 << 192, poolState.sqrtPrice * poolState.sqrtPrice
            );
            (uint256 floor0,) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            floor0 = FixedPointMathLib.max(floor0, 1);
            (uint256 held0,,,) = stagedAmounts(poolState, range, floor0, ceiling1);
            coreState.buffer0 =
                bound(coreState.buffer0, held0 >= needed ? floor0 : ceiling0 - (top0 - needed), ceiling0);
        }
        {
            (uint256 held0, uint256 top1,,) = stagedAmounts(poolState, range, coreState.buffer0, ceiling1);
            uint256 needed = least.zeroFloorSub(token0ToToken1(poolState.sqrtPrice, held0));
            (, uint256 floor1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            floor1 = FixedPointMathLib.max(floor1, 1);
            (, uint256 held1,,) = stagedAmounts(poolState, range, coreState.buffer0, floor1);
            coreState.buffer1 =
                bound(coreState.buffer1, held1 >= needed ? floor1 : ceiling1 - (top1 - needed), ceiling1);
        }
        uint256 value;
        {
            (uint256 held0, uint256 held1,,) = stagedAmounts(poolState, range, coreState.buffer0, coreState.buffer1);
            value = held1 + token0ToToken1(poolState.sqrtPrice, held0);
        }

        // And: A supply up to the vault's value, each share worth over a token0 wei.
        uint256 floor = Constants.DEAD_SHARES;
        uint256 ceiling = FixedPointMathLib.min(
            coreState.buffer1 + token0ToToken1(poolState.sqrtPrice, coreState.buffer0), Constants.MAX_FUZZED_AMOUNT
        );
        ceiling = FixedPointMathLib.max(ceiling, floor);
        if (price != 0) ceiling = FixedPointMathLib.min(ceiling, (value - 1) / price);
        coreState.supply = bound(coreState.supply, floor, ceiling);
    }

    function givenBufferPaysShares(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range,
        uint256 shares0,
        uint256 shares1
    ) internal view {
        // And: Buffers paying the shares, each share worth a wei, the supply an amount.
        uint256 floor = Constants.DEAD_SHARES + 2 * FixedPointMathLib.max(shares0, shares1);
        {
            (uint256 amount0, uint256 amount1) = amountsRoundedUp(
                sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity + range.liquidityStaked
            );
            uint256 most = amount1 + (amount1 > 0 ? amount1 : Constants.MAX_FUZZED_AMOUNT / 4)
                + token0ToToken1(
                    poolState.sqrtPrice, amount0 + (amount0 > 0 ? amount0 : Constants.MAX_FUZZED_AMOUNT / 4)
                );
            amount0 = FixedPointMathLib.max(floor, (2 * shares0 * most).divUp(Constants.MAX_FUZZED_AMOUNT));
            amount0 = shares0 == 0 ? 0 : amount0.fullMulDivUp(1 << 192, poolState.sqrtPrice * poolState.sqrtPrice) + 1;
            amount1 = FixedPointMathLib.max(floor, (2 * shares1 * most).divUp(Constants.MAX_FUZZED_AMOUNT));
            givenValidCoreState(coreState, poolState, range, 0, amount0, shares1 == 0 ? 0 : amount1 + 1);
        }
        uint256 value;
        {
            (uint256 amount0, uint256 amount1, uint256 principal0, uint256 principal1) =
                stagedAmounts(poolState, range, coreState.buffer0, coreState.buffer1);
            value = amount1 + token0ToToken1(poolState.sqrtPrice, amount0);
            if (shares0 != 0) {
                uint256 paid = token0ToToken1(poolState.sqrtPrice, amount0 - principal0);
                floor = FixedPointMathLib.max(floor, (shares0 * value).divUp(paid));
            }
            if (shares1 != 0) floor = FixedPointMathLib.max(floor, (shares1 * value).divUp(amount1 - principal1));
        }
        uint256 ceiling = FixedPointMathLib.min(value, Constants.MAX_FUZZED_AMOUNT);
        coreState.supply = bound(coreState.supply, floor, FixedPointMathLib.max(ceiling, floor));
    }

    function givenShareWorthLessThanToken0(
        CoreState memory coreState,
        PoolState memory poolState,
        RangeState memory range
    ) internal view {
        // And: A supply each share of which is worth less than a token0 wei.
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        (uint256 amount0, uint256 amount1,,) = stagedAmounts(poolState, range, coreState.buffer0, coreState.buffer1);
        uint256 value = amount1 + token0ToToken1(poolState.sqrtPrice, amount0);
        uint256 asset = uint256(1).fullMulDivUp(poolState.sqrtPrice * poolState.sqrtPrice, 1 << 192);
        uint256 floor = FixedPointMathLib.max(Constants.DEAD_SHARES + 2, (value + 1).divUp(asset));
        coreState.supply = bound(coreState.supply, floor, FixedPointMathLib.max(Constants.MAX_FUZZED_AMOUNT, floor));
    }

    function setCoreState(CoreState memory coreState) internal {
        vm.startPrank(factory);
        almCore.setPerUserCap(type(uint128).max);
        almCore.setTotalCap(type(uint128).max);
        vm.stopPrank();

        uint256 shares = FixedPointMathLib.max(coreState.supply, almCore.DEAD_SHARES_() + 1);
        token0.mint(users.steward, coreState.buffer0);
        token1.mint(users.steward, coreState.buffer1);
        vm.startPrank(users.steward);
        token0.approve(factory, coreState.buffer0);
        token1.approve(factory, coreState.buffer1);
        deployer.seedCore(address(almCore), coreState.buffer0, coreState.buffer1, shares, users.steward);
        vm.stopPrank();
        if (shares > coreState.supply) almCore.burnShares(users.steward, shares - coreState.supply);

        coreState.supply = almCore.totalSupply();
        coreState.buffer0 = almCore.bufferAmount0();
        coreState.buffer1 = almCore.bufferAmount1();
    }

    /* //////////////////////////////////////////////////////////////
                               RANGE STATE
    ////////////////////////////////////////////////////////////// */

    function givenValidRangeState(RangeState memory range, PoolState memory poolState, bool aroundSpot) internal view {
        // And: A range in the other providers' position, around the price or anywhere.
        int24 tickSpacing = poolState.tickSpacing;
        int24 tickUpper = bandTick(tickSpacing) / tickSpacing;
        range.tickLower = int24(
            bound(
                range.tickLower / tickSpacing,
                -tickUpper + 1,
                aroundSpot ? (poolState.tickCurrent - tickSpacing) / tickSpacing : tickUpper - 2
            )
        ) * tickSpacing;
        range.tickUpper = int24(
            bound(
                range.tickUpper / tickSpacing,
                aroundSpot ? (poolState.tickCurrent + tickSpacing) / tickSpacing : range.tickLower / tickSpacing + 1,
                tickUpper - 1
            )
        ) * tickSpacing;

        // And: An unstaked leg and a staked leg of none to a quarter of the room each.
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidity = uint128(bound(range.liquidity, Constants.MIN_FUZZED_LIQUIDITY, free / 4));
        range.liquidityStaked = uint128(bound(range.liquidityStaked, 0, free / 4));
    }

    function givenValidRangeState(RangeState memory range, PoolState memory poolState, bool aroundSpot, bool staked)
        internal
        view
    {
        givenValidRangeState(range, poolState, aroundSpot);

        // And: A staked leg from the floor to a quarter of the room, or none.
        uint128 free = liquidityCeiling(range.tickLower, range.tickUpper, Constants.MIN_FUZZED_LIQUIDITY);
        range.liquidityStaked =
            staked ? uint128(bound(range.liquidityStaked, Constants.MIN_FUZZED_LIQUIDITY, free / 4)) : 0;
    }

    function givenRangeRoom(RangeState memory range, PoolState memory poolState, bool zeroForOne) internal pure {
        // And: A full spacing between the price and the edge a trade moves towards.
        int24 tickSpacing = poolState.tickSpacing;
        int24 band = bandTick(tickSpacing) / tickSpacing;
        int24 spot = poolState.tickCurrent / tickSpacing;
        if (poolState.tickCurrent < 0 && poolState.tickCurrent % tickSpacing != 0) --spot;
        if (zeroForOne) {
            range.tickLower = int24(bound(range.tickLower / tickSpacing, -band + 1, spot - 1)) * tickSpacing;
        } else {
            range.tickUpper = int24(bound(range.tickUpper / tickSpacing, spot + 2, band - 1)) * tickSpacing;
        }
    }

    function setRangeState(RangeState memory range) internal {
        range.index = almCore.getRangesLength();
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        fundShortfall(amount0, amount1);
        runStagingPlan(Plan.init().openRange(range.tickLower, range.tickUpper, amount0, amount1, 0, 0));
        if (range.liquidityStaked != 0) {
            (amount0, amount1) =
                amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidityStaked);
            fundShortfall(amount0, amount1);
            runStagingPlan(
                Plan.init().stake(range.index, almCore.getRange(range.index).unstakedTokenId, amount0, amount1, 0, 0)
            );
        }

        Range memory staged = almCore.getRange(range.index);
        (range.liquidity, range.liquidityStaked) = (positionLiquidity(staged.unstakedTokenId), staged.stakedLiquidity);
        (range.unstakedTokenId, range.stakedTokenId) = (staged.unstakedTokenId, staged.stakedTokenId);
    }

    function stagedAmounts(PoolState memory poolState, RangeState memory range, uint256 buffer0, uint256 buffer1)
        internal
        pure
        returns (uint256 amount0, uint256 amount1, uint256 principal0, uint256 principal1)
    {
        // The tokens setRangeState leaves of these buffers, and their part in the range.
        (uint256 leg0, uint256 leg1) =
            amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidity);
        (amount0, amount1) = (FixedPointMathLib.max(buffer0, leg0), FixedPointMathLib.max(buffer1, leg1));
        uint128 liquidity =
            liquidityForAmounts(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, leg0, leg1);
        (leg0, leg1) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, liquidity);
        (amount0, amount1) = (amount0 - leg0, amount1 - leg1);
        if (range.liquidityStaked != 0) {
            (leg0, leg1) = amountsRoundedUp(
                uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, range.liquidityStaked
            );
            (amount0, amount1) = (FixedPointMathLib.max(amount0, leg0), FixedPointMathLib.max(amount1, leg1));
            uint128 staked =
                liquidityForAmounts(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, leg0, leg1);
            (leg0, leg1) = amountsRoundedUp(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, staked);
            (amount0, amount1) = (amount0 - leg0, amount1 - leg1);
            liquidity += staked;
        }
        (principal0, principal1) =
            amountsRoundedDown(uint160(poolState.sqrtPrice), range.tickLower, range.tickUpper, liquidity);
        (amount0, amount1) = (amount0 + principal0, amount1 + principal1);
    }

    function stageRange(address owner, RangeState memory range) internal returns (Range memory staged) {
        (staged.tickLower, staged.tickUpper) = (range.tickLower, range.tickUpper);
        bool drained = range.liquidity == 0;
        (range.unstakedTokenId, range.liquidity) = mintPositionFor(
            pool,
            users.liquidityProvider,
            owner,
            range.tickLower,
            range.tickUpper,
            drained ? Constants.MIN_FUZZED_LIQUIDITY : range.liquidity
        );
        staged.unstakedTokenId = SafeCastLib.toUint80(range.unstakedTokenId);
        if (drained) {
            vm.startPrank(owner);
            POSITION_MANAGER.decreaseLiquidity(
                INonfungiblePositionManager.DecreaseLiquidityParams({
                    tokenId: range.unstakedTokenId,
                    liquidity: range.liquidity,
                    amount0Min: 0,
                    amount1Min: 0,
                    deadline: vm.getBlockTimestamp()
                })
            );
            POSITION_MANAGER.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: range.unstakedTokenId,
                    recipient: owner,
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
            vm.stopPrank();
            range.liquidity = 0;
        }
        if (range.liquidityStaked != 0) {
            (range.stakedTokenId, range.liquidityStaked) = mintPositionFor(
                pool, users.liquidityProvider, owner, range.tickLower, range.tickUpper, range.liquidityStaked
            );
            stake(gauge, owner, range.stakedTokenId);
            staged.stakedLiquidity = range.liquidityStaked;
            staged.stakedTokenId = SafeCastLib.toUint80(range.stakedTokenId);
            staged.stakedBlock = SafeCastLib.toUint48(vm.getBlockNumber());
        }
    }

    /* //////////////////////////////////////////////////////////////
                              CONFIG STATE
    ////////////////////////////////////////////////////////////// */

    function givenValidConfigState(ConfigState memory configState) internal pure {
        // And: Caps below, at or over the supply, set ones as the configured check needs.
        configState.totalCap = bound(configState.totalCap, 1, type(uint128).max);
        configState.perUserCap = bound(configState.perUserCap, 1, type(uint128).max);

        // And: Plan limits and price bands storage holds.
        givenValidPlanLimits(configState, 0, 0);
        configState.maxDeviation = bound(configState.maxDeviation, 0, type(uint64).max);

        // And: Protocol fees up to their cap.
        configState.protocolEmissionFeeBps = uint16(bound(configState.protocolEmissionFeeBps, 0, ConfigLib.MAX_FEE_BPS));
        configState.protocolSwapFeeBps = uint16(bound(configState.protocolSwapFeeBps, 0, ConfigLib.MAX_FEE_BPS));
    }

    function setConfigState(ConfigState memory configState) internal {
        vm.startPrank(factory);
        almCore.setTotalCap(configState.totalCap);
        almCore.setPerUserCap(configState.perUserCap);
        almCore.setPlanLimits(configState.maxShortfallBps, configState.maxSwapCostBps, 0);
        almCore.setDeviation(
            Constants.TWAP_WINDOW, configState.maxDeviation, configState.maxDeviation, configState.maxDeviation
        );
        almCore.setProtocolFees(configState.protocolEmissionFeeBps, configState.protocolSwapFeeBps, users.feeRecipient);
        if (configState.paused) almCore.pause();
        vm.stopPrank();
    }

    function givenValidPlanLimits(ConfigState memory configState, uint256 shortfallBps, uint256 swapCostBps)
        internal
        pure
    {
        // And: Plan limits storage holds, from the least the plan needs.
        configState.maxShortfallBps =
            uint16(bound(configState.maxShortfallBps, shortfallBps, ConfigLib.BPS_DENOMINATOR));
        configState.maxSwapCostBps =
            uint16(bound(configState.maxSwapCostBps, swapCostBps, ConfigLib.BPS_DENOMINATOR - 1));
    }

    function givenValidPlanLimits(
        ConfigState memory configState,
        uint256 steps,
        bool zeroForOne,
        uint256 amountIn,
        uint256 amountOut
    ) internal view {
        // And: Plan limits storage holds, from the swap's cost and the plan's loss.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 cost = zeroForOne
            ? amountIn.fullMulDivUp(sqrtPrice * sqrtPrice, 1 << 192).zeroFloorSub(amountOut)
            : amountIn.zeroFloorSub(token0ToToken1(sqrtPrice, amountOut));
        givenValidPlanLimits(
            configState, leastShortfallBps(steps, cost), leastSwapCostBps(zeroForOne, amountIn, amountOut)
        );
    }

    function setSpotFromTwap(uint256 maxSpotFromTwap) internal {
        // The band between spot and the TWAP, the window and the trusted bands kept.
        (uint32 window, uint256 maxSpotFromTrusted, uint256 maxTwapFromTrusted) =
            (almCore.twapWindow_(), almCore.maxSpotFromTrusted_(), almCore.maxTwapFromTrusted_());
        vm.prank(factory);
        almCore.setDeviation(window, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted);
    }

    function spotFromTwap(bool roundUp) internal view returns (uint256 deviation) {
        deviation = sqrtDeviation(sqrtPriceX96(pool), almCore.meanSqrtPriceX96_(), roundUp);
    }

    function sqrtDeviation(uint256 sqrtPriceA, uint256 sqrtPriceB, bool roundUp)
        internal
        pure
        returns (uint256 deviation)
    {
        // The 1e18-scaled distance between two sqrt prices.
        (uint256 high, uint256 low) = sqrtPriceA > sqrtPriceB ? (sqrtPriceA, sqrtPriceB) : (sqrtPriceB, sqrtPriceA);
        deviation = (roundUp ? high.fullMulDivUp(1e18, low) : high.fullMulDiv(1e18, low)) - 1e18;
    }

    function outsideBand(uint256 deviation, uint256 distance) internal pure returns (uint256 bounded) {
        // A band narrower than a distance rounded down, within storage.
        bounded = bound(deviation, 0, FixedPointMathLib.min(distance - 1, type(uint64).max));
    }

    function insideBand(uint256 deviation, uint256 distance) internal pure returns (uint256 bounded) {
        // A band at least a distance rounded up, within storage.
        bounded = bound(deviation, distance, type(uint64).max);
    }

    function setTrustedDeviation(uint256 maxSpotFromTrusted, uint256 maxTwapFromTrusted) internal {
        // The bands around a trusted price, the window and the TWAP band kept.
        (uint32 window, uint256 maxSpotFromTwap) = (almCore.twapWindow_(), almCore.maxSpotFromTwap_());
        vm.prank(factory);
        almCore.setDeviation(window, maxSpotFromTwap, maxSpotFromTrusted, maxTwapFromTrusted);
    }

    function setPlanLimits(ConfigState memory configState) internal {
        vm.prank(factory);
        almCore.setPlanLimits(configState.maxShortfallBps, configState.maxSwapCostBps, 0);
    }

    /* //////////////////////////////////////////////////////////////
                               QUEUE STATE
    ////////////////////////////////////////////////////////////// */

    function givenValidQueueState(QueueState memory queueState, uint256 least0, uint256 least1) internal view {
        givenValidQueueState(queueState, least0, least1, Constants.ALL_QUEUES);
    }

    function givenValidQueueState(QueueState memory queueState, uint256 least0, uint256 least1, uint8 queues)
        internal
        view
    {
        // And: A pending deposit per vault from its floor, its pending aLP a uint96.
        (uint256 supplyPerValueX128, uint160 lastSqrtPrice) = almCore.lastExchangeRate_();
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 upper = FixedPointMathLib.max(sqrtPrice, lastSqrtPrice);
        uint256 ceiling = uint256(type(uint96).max).fullMulDiv(1 << 128, supplyPerValueX128);
        uint256 ceiling0 = ceiling.fullMulDiv(1 << 96, upper).fullMulDiv(1 << 96, upper);
        uint256 lower = FixedPointMathLib.min(sqrtPrice, lastSqrtPrice);
        uint256 ceiling1 = ceiling.fullMulDiv(lower, lastSqrtPrice).fullMulDiv(lower, lastSqrtPrice);
        ceiling0 = FixedPointMathLib.min(ceiling0 / 2, Constants.MAX_FUZZED_AMOUNT / 4);
        ceiling1 = FixedPointMathLib.min(ceiling1 / 2, Constants.MAX_FUZZED_AMOUNT / 4);
        // A hole: a core whose least deposit prices its pending aLP past a uint96.
        vm.assume(least0 <= ceiling0 && least1 <= ceiling1);
        queueState.deposit0 =
            bound(queueState.deposit0, least0, (queues & Constants.QUEUE_DEPOSIT0) != 0 ? ceiling0 : least0);
        queueState.deposit1 =
            bound(queueState.deposit1, least1, (queues & Constants.QUEUE_DEPOSIT1) != 0 ? ceiling1 : least1);

        // And: A pending redeem per open vault of up to half the seed receiver's aLP.
        uint256 held = almCore.balanceOf(users.steward);
        queueState.redeem0 = bound(queueState.redeem0, 0, (queues & Constants.QUEUE_REDEEM0) != 0 ? held / 2 : 0);
        queueState.redeem1 = bound(queueState.redeem1, 0, (queues & Constants.QUEUE_REDEEM1) != 0 ? held / 2 : 0);
    }

    function givenAPendingRequest(QueueState memory queueState, bool isToken0, bool isDeposit) internal view {
        // And: Pending requests, at least one in the given queue.
        givenValidQueueState(queueState, isDeposit && isToken0 ? 1 : 0, isDeposit && !isToken0 ? 1 : 0);
        uint256 held = almCore.balanceOf(users.steward) / 2;
        if (!isDeposit && isToken0) queueState.redeem0 = bound(queueState.redeem0, 1, held);
        if (!isDeposit && !isToken0) queueState.redeem1 = bound(queueState.redeem1, 1, held);
    }

    function givenDepositWithinTheRange(QueueState memory queueState, RangeState memory range) internal view {
        // And: A token0 deposit of up to the range's token0.
        (uint256 amount0,) = amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, range.liquidity);
        if (queueState.deposit0 > amount0) queueState.deposit0 = bound(queueState.deposit0, 1, amount0);
    }

    function setQueueState(QueueState memory queueState) internal {
        if (queueState.deposit0 != 0) recordDepositAt(asyncVault0, accountB, queueState.deposit0);
        if (queueState.deposit1 != 0) recordDepositAt(asyncVault1, accountC, queueState.deposit1);
        vm.startPrank(users.steward);
        almCore.transfer(controller, queueState.redeem0);
        almCore.transfer(secondController, queueState.redeem1);
        vm.stopPrank();
        if (queueState.redeem0 != 0) {
            vm.prank(asyncVault0);
            almCore.recordRedeemRequest(controller, controller, controller, queueState.redeem0);
        }
        if (queueState.redeem1 != 0) {
            vm.prank(asyncVault1);
            almCore.recordRedeemRequest(secondController, secondController, secondController, queueState.redeem1);
        }
    }

    /* //////////////////////////////////////////////////////////////
                               SETTLEMENT
    ////////////////////////////////////////////////////////////// */

    function givenTrustedPrice(uint256 trustedSqrtPriceX96) internal view returns (uint160 bounded) {
        // And: A trusted price inside the band around spot.
        (uint256 lower, uint256 upper) = CLMath.getBand(sqrtPriceX96(pool), almCore.maxSpotFromTrusted_());
        bounded = uint160(bound(trustedSqrtPriceX96, lower, upper));
    }

    function openWholeBuffer(Plan.Steps memory plan, RangeState memory range)
        internal
        pure
        returns (Plan.Steps memory)
    {
        // A range opened with the whole buffer.
        uint256 all = Sentinels.OPEN_BALANCE | ConfigLib.BPS_DENOMINATOR;
        return plan.openRange(range.tickLower, range.tickUpper, all, all, 0, 0);
    }

    function expectInvalidOrder(Plan.Steps memory plan, uint160 trustedSqrtPriceX96) internal {
        vm.prank(users.keeper);
        vm.expectRevert(ALMKeeperExtension.InvalidOrder.selector);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    /* //////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function partialEntriesLength(uint256 seed) internal pure returns (uint256 length) {
        // A queue payload length short of the queue or with a partial controller.
        seed = bound(seed, 0, type(uint16).max);
        if (seed < CalldataLogic.QUEUE_LENGTH) return seed;
        seed -= CalldataLogic.QUEUE_LENGTH;
        uint256 partials = CalldataLogic.CONTROLLER_LENGTH - 1;
        length = CalldataLogic.QUEUE_LENGTH + seed / partials * CalldataLogic.CONTROLLER_LENGTH + seed % partials + 1;
    }

    function bandTick(int24 tickSpacing) internal pure returns (int24 tick) {
        tick = TickMath.getTickAtSqrtPrice(Constants.BOUND_SQRT_PRICE_UPPER) / tickSpacing * tickSpacing;
    }

    function fundShortfall(uint256 amount0, uint256 amount1) internal {
        fundBuffer(amount0.zeroFloorSub(almCore.bufferAmount0()), amount1.zeroFloorSub(almCore.bufferAmount1()));
    }

    function fundBuffer(uint256 amount0, uint256 amount1) internal {
        if (almCore.totalSupply() == 0) almCore.mintShares(address(1), Constants.DEAD_SHARES);
        token0.mint(address(almCore), amount0);
        token1.mint(address(almCore), amount1);
        almCore.setBuffers(almCore.bufferAmount0() + amount0, almCore.bufferAmount1() + amount1);
    }

    function donateToRange(RangeState memory range, uint128 liquidity) internal {
        (uint256 amount0, uint256 amount1) =
            amountsRoundedUp(sqrtPriceX96(pool), range.tickLower, range.tickUpper, liquidity);
        token0.mint(users.unprivilegedAddress, amount0);
        token1.mint(users.unprivilegedAddress, amount1);
        vm.startPrank(users.unprivilegedAddress);
        token0.approve(address(POSITION_MANAGER), amount0);
        token1.approve(address(POSITION_MANAGER), amount1);
        POSITION_MANAGER.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: range.unstakedTokenId,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                deadline: vm.getBlockTimestamp()
            })
        );
        vm.stopPrank();
    }

    function runPlan(Plan.Steps memory plan) internal {
        uint160 trustedSqrtPriceX96 = sqrtPriceX96(pool);
        vm.prank(users.keeper);
        almCore.execute(plan.commands, plan.inputs, trustedSqrtPriceX96);
    }

    function runStagingPlan(Plan.Steps memory plan) internal {
        // A plan at the shortfall a wei per token covers, the test's limits restored.
        (uint256 maxShortfallBps, uint256 maxSwapCostBps, uint256 minPlanInterval) =
            (almCore.maxShortfallBps_(), almCore.maxSwapCostBps_(), almCore.minPlanInterval_());
        uint256 leastBps = leastShortfallBps(1, 0);
        vm.prank(factory);
        almCore.setPlanLimits(uint16(leastBps), 0, 0);
        runPlan(plan);
        vm.prank(factory);
        almCore.setPlanLimits(uint16(maxShortfallBps), uint16(maxSwapCostBps), uint32(minPlanInterval));
    }

    function recordDepositAt(address vault, address controller_, uint256 assets) internal {
        (vault == asyncVault0 ? token0 : token1).mint(address(almCore), assets);
        vm.prank(vault);
        almCore.recordDepositRequest(controller_, assets);
    }

    function recordRedeemAt(address vault, address controller_, uint256 shares) internal {
        almCore.mintShares(controller_, shares);
        vm.prank(vault);
        almCore.recordRedeemRequest(controller_, controller_, controller_, shares);
    }

    function readDuringPlan(address target, bytes memory probe) internal returns (bool success, bytes memory result) {
        LockProbeRouterMock router = new LockProbeRouterMock();
        router.arm(target, probe);
        fundBuffer(1, 0);
        uint256 amountOut = token0ToToken1(sqrtPriceX96(pool), 1) + 1;
        bytes memory data = abi.encodeCall(
            LockProbeRouterMock.swap, (address(token0), address(token1), 1, amountOut, address(routerTrampoline))
        );
        runStagingPlan(Plan.init().swapViaRouter(address(router), 1, true, 0, data));
        (success, result) = (router.success(), router.result());
    }

    function liquidityCeiling(int24 tickLower, int24 tickUpper, uint128 floor) internal view returns (uint128 ceiling) {
        // Half the liquidity the fuller edge still takes, its amounts within an amount.
        (uint128 lower,,,,,,,,,) = pool.ticks(tickLower);
        (uint128 upper,,,,,,,,,) = pool.ticks(tickUpper);
        uint256 free = tickSpacingToMaxLiquidityPerTick(pool.tickSpacing()) - FixedPointMathLib.max(lower, upper);
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(pool), tickLower, tickUpper, uint128(free));
        uint256 worth = FixedPointMathLib.max(amount0, amount1);
        if (worth > Constants.MAX_FUZZED_AMOUNT) free = free.fullMulDiv(Constants.MAX_FUZZED_AMOUNT, worth);
        ceiling = uint128(FixedPointMathLib.max(free / 2, floor));
    }

    function mintOvershoot(uint256 sqrtPrice, int24 tickLower, int24 tickUpper) internal pure returns (uint256 slack) {
        // The most liquidity a mint of rounded-up amounts takes past what it was sized for.
        uint256 lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint256 upper = TickMath.getSqrtPriceAtTick(tickUpper);
        if (sqrtPrice <= lower) {
            slack = (lower.fullMulDiv(upper, 1 << 96) - 1) / (upper - lower);
        } else if (sqrtPrice < upper) {
            slack = FixedPointMathLib.min(
                (sqrtPrice.fullMulDiv(upper, 1 << 96) - 1) / (upper - sqrtPrice), ((1 << 96) - 1) / (sqrtPrice - lower)
            );
        } else {
            slack = ((1 << 96) - 1) / (upper - lower);
        }
    }

    function token0ToToken1(uint256 sqrtPrice, uint256 amount0) internal pure returns (uint256 amount1) {
        amount1 = amount0.fullMulDiv(sqrtPrice * sqrtPrice, 1 << 192);
    }

    function token1ToToken0(uint256 sqrtPrice, uint256 amount1) internal pure returns (uint256 amount0) {
        amount0 = amount1.fullMulDiv(1 << 192, sqrtPrice * sqrtPrice);
    }

    function leastSwapIn(bool zeroForOne) internal view returns (uint256 least) {
        // Sixteen wei of the input, the output at spot and the sqrt price.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 priceX192 = sqrtPrice * sqrtPrice;
        uint256 move = 16 * uint256(pool.liquidity());
        least = zeroForOne
            ? FixedPointMathLib.max(
                uint256(16).fullMulDivUp(1 << 192, priceX192), move.fullMulDivUp(1 << 96, sqrtPrice).divUp(sqrtPrice)
            )
            : FixedPointMathLib.max(uint256(16).fullMulDivUp(priceX192, 1 << 192), move.divUp(1 << 96));
        least = FixedPointMathLib.max(least, 16);
    }

    function spacingSwapIn(uint256 amountIn, bool zeroForOne) internal view returns (uint256 bounded) {
        // An input of the least or more, inside the current tick spacing.
        int24 tickSpacing = pool.tickSpacing();
        int24 tick = currentTick(pool);
        int24 tickBelow = tick - (tick % tickSpacing + tickSpacing) % tickSpacing;
        uint160 edge = TickMath.getSqrtPriceAtTick(zeroForOne ? tickBelow : tickBelow + tickSpacing);
        uint256 ceiling = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(edge, sqrtPriceX96(pool), pool.liquidity(), true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceX96(pool), edge, pool.liquidity(), true);
        bounded =
            bound(amountIn, leastSwapIn(zeroForOne), FixedPointMathLib.min(ceiling - 1, Constants.MAX_FUZZED_AMOUNT));
    }

    function maxSwapLoss(uint256 value, uint256 maxSwapCostBps) internal pure returns (uint256 loss) {
        loss = value - value.fullMulDivUp(ConfigLib.BPS_DENOMINATOR - maxSwapCostBps, ConfigLib.BPS_DENOMINATOR);
    }

    function setPlanLimitsAtTheSwapCost(uint256 steps, uint256 maxSwapCostBps, uint160 trustedSqrtPriceX96) internal {
        // A shortfall covering the value at the max swap cost and the trusted price.
        uint256 ratio = sqrtDeviation(sqrtPriceX96(pool), trustedSqrtPriceX96, true) + 1e18;
        uint256 value = vaultValue(trustedSqrtPriceX96, true);
        uint256 loss =
            maxSwapLoss(value, maxSwapCostBps) + value.fullMulDivUp(ratio.fullMulDivUp(ratio, 1e18) - 1e18, 1e18);
        uint256 leastBps = leastShortfallBps(steps, loss);
        vm.prank(factory);
        almCore.setPlanLimits(uint16(leastBps), uint16(maxSwapCostBps), 0);
    }

    function leastShortfallBps(uint256 steps, uint256 loss) internal view returns (uint256 bps) {
        // A wei of each token per step, the loss and a wei, over the vault's least value.
        uint256 value = vaultValue(sqrtPriceX96(pool), false);
        loss += steps * (token0ToToken1(sqrtPriceX96(pool), 1) + 2) + 1;
        bps = value == 0
            ? ConfigLib.BPS_DENOMINATOR
            : FixedPointMathLib.min(loss.fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value), ConfigLib.BPS_DENOMINATOR);
    }

    function mostShortfallBps(uint256 loss) internal view returns (uint256 bps) {
        // The most bps a loss of at least this exceeds, over the vault's greatest value.
        bps = loss < 2
            ? 0
            : FixedPointMathLib.min(
                (loss - 1) * ConfigLib.BPS_DENOMINATOR / vaultValue(sqrtPriceX96(pool), true), ConfigLib.BPS_DENOMINATOR
            );
    }

    function vaultValue(uint160 sqrtPrice, bool roundUp) internal view returns (uint256 value) {
        // The buffer and every range's principal at a price, without uncollected fees.
        (uint256 amount0, uint256 amount1) = (almCore.bufferAmount0(), almCore.bufferAmount1());
        for (uint256 i; i < almCore.getRangesLength(); ++i) {
            Range memory staged = almCore.getRange(i);
            uint128 liquidity = staged.stakedLiquidity;
            if (staged.unstakedTokenId != 0) liquidity += positionLiquidity(staged.unstakedTokenId);
            (uint256 principal0, uint256 principal1) = roundUp
                ? amountsRoundedUp(sqrtPrice, staged.tickLower, staged.tickUpper, liquidity)
                : amountsRoundedDown(sqrtPrice, staged.tickLower, staged.tickUpper, liquidity);
            (amount0, amount1) = (amount0 + principal0, amount1 + principal1);
        }
        value = token0ToToken1(sqrtPrice, amount0) + amount1;
    }

    function poolSwapOut(bool zeroForOne, uint256 amountIn) internal returns (uint256 amountOut) {
        // The pool's output for an input, from a trader's swap that is rolled back.
        uint256 snapshot = vm.snapshotState();
        (ERC20Mock tokenIn, ERC20Mock tokenOut) = zeroForOne ? (token0, token1) : (token1, token0);
        amountOut = swapInPool(pool, users.unprivilegedAddress, address(tokenIn), address(tokenOut), amountIn);
        vm.revertToState(snapshot);
    }

    function leastSwapCostBps(bool zeroForOne, uint256 amountIn, uint256 amountOut)
        internal
        view
        returns (uint256 bps)
    {
        // The share of the input's value at spot the output falls short of, rounded up.
        uint256 sqrtPrice = sqrtPriceX96(pool);
        uint256 value = zeroForOne ? token0ToToken1(sqrtPrice, amountIn) : token1ToToken0(sqrtPrice, amountIn);
        bps = value > amountOut ? (value - amountOut).fullMulDivUp(ConfigLib.BPS_DENOMINATOR, value) : 0;
    }
}

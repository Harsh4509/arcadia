/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../Constants.sol";
import { ERC20Mock } from "../../mocks/ERC20Mock.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { ICLFactory } from "./interfaces/ICLFactory.sol";
import { ICLGauge } from "./interfaces/ICLGauge.sol";
import { ICLGaugeFactory } from "./interfaces/ICLGaugeFactory.sol";
import { ICLPool } from "./interfaces/ICLPool.sol";
import { IERC721 } from "@forge-std/interfaces/IERC721.sol";
import { IMetadexCLGauge } from "../../../../src/interfaces/IMetadexCLGauge.sol";
import { IMetadexCLPool } from "../../../../src/interfaces/IMetadexCLPool.sol";
import { IMetadexSwapRouter } from "./interfaces/IMetadexSwapRouter.sol";
import { INonfungiblePositionManager } from "./interfaces/INonfungiblePositionManager.sol";
import { ISwapRouter } from "./interfaces/ISwapRouter.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { MetadexFixture } from "./MetadexFixture.f.sol";
import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { SqrtPriceMath } from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import { SwapMath } from "@uniswap/v4-core/src/libraries/SwapMath.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Deploys the Metadex Slipstream CL stack from the pinned bytecode on top of the voter stack.
 */
// forge-lint: disable-next-item(unsafe-typecast, unused-return)
abstract contract MetadexCLFixture is MetadexFixture {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    uint256 internal constant MAX_MIN_STAKE_BLOCKS = type(uint128).max;

    // The sqrt price of one.
    uint160 internal constant SQRT_PRICE_ONE_X96 = 1 << 96;

    // The liquidity every pool of a route is seeded with.
    uint128 internal constant ROUTE_LIQUIDITY = 1e24;

    // The observations every pool keeps.
    uint16 internal constant OBSERVATION_CARDINALITY = 300;

    // The lowest tick a route pool's liquidity spans.
    int24 internal constant ROUTE_TICK_LOWER = -1000 * TICK_SPACING;

    // The highest tick a route pool's liquidity spans.
    int24 internal constant ROUTE_TICK_UPPER = 1000 * TICK_SPACING;

    // The lowest tick a position of that spacing takes.
    int24 internal constant TICK_LOWER = TickMath.MIN_TICK - (TickMath.MIN_TICK % TICK_SPACING);

    // The tick spacing every pool is created with.
    int24 internal constant TICK_SPACING = 200;

    // The highest tick a position of that spacing takes.
    int24 internal constant TICK_UPPER = TickMath.MAX_TICK - (TickMath.MAX_TICK % TICK_SPACING);

    // Must match the address foundry.toml links the CL pool library against.
    address internal constant CL_POOL_NON_SWAP_PATH = 0x3000000000000000000000000000000000000005;

    address internal constant POOL_IMPLEMENTATION = 0x2000000000000000000000000000000000000001;

    ICLFactory internal constant CL_FACTORY = ICLFactory(0x2000000000000000000000000000000000000002);

    INonfungiblePositionManager internal constant POSITION_MANAGER =
        INonfungiblePositionManager(0x2000000000000000000000000000000000000003);

    ISwapRouter internal constant SWAP_ROUTER = ISwapRouter(0x2000000000000000000000000000000000000004);

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    ICLGaugeFactory internal clGaugeFactory;

    /* //////////////////////////////////////////////////////////////
                                  ERRORS
    ////////////////////////////////////////////////////////////// */

    error MintShort();

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function deployMetadexCL() internal {
        deployCodeTo("out/CLPoolNonSwapPath.sol/CLPoolNonSwapPath.json", CL_POOL_NON_SWAP_PATH);
        vm.label(CL_POOL_NON_SWAP_PATH, "CLPoolNonSwapPath");
        deployCodeTo("out/CLPool.sol/CLPool.json", POOL_IMPLEMENTATION);
        vm.label(POOL_IMPLEMENTATION, "CLPoolImplementation");

        ICLFactory.FeeTier[] memory feeTiers = new ICLFactory.FeeTier[](5);
        feeTiers[0] = ICLFactory.FeeTier({ tickSpacing: 1, fee: 100 });
        feeTiers[1] = ICLFactory.FeeTier({ tickSpacing: 50, fee: 500 });
        feeTiers[2] = ICLFactory.FeeTier({ tickSpacing: 100, fee: 500 });
        feeTiers[3] = ICLFactory.FeeTier({ tickSpacing: 200, fee: 3000 });
        feeTiers[4] = ICLFactory.FeeTier({ tickSpacing: 2000, fee: 10_000 });
        bytes memory args = abi.encode(
            ICLFactory.ConstructorParams({
                owner: address(this),
                swapFeeManager: address(this),
                unstakedFeeManager: address(this),
                voter: address(leafVoter),
                poolImplementation: POOL_IMPLEMENTATION,
                positionManager: address(POSITION_MANAGER),
                factoryRegistry: address(factoryRegistry),
                defaultSwapHook: address(0),
                discountRegistryManager: address(this),
                clPoolTapeManager: address(this),
                initialFeeTiers: feeTiers
            })
        );
        deployCodeTo("out/CLFactory.sol/CLFactory.json", args, address(CL_FACTORY));
        vm.label(address(CL_FACTORY), "CLFactory");

        args = abi.encode(address(this), address(CL_FACTORY), address(weth), address(0), "Metadex Positions", "MDX-POS");
        deployCodeTo(
            "out/NonfungiblePositionManager.sol/NonfungiblePositionManager.json", args, address(POSITION_MANAGER)
        );
        vm.label(address(POSITION_MANAGER), "NonfungiblePositionManager");

        deployCodeTo(
            "out/SwapRouter.sol/SwapRouter.json", abi.encode(address(CL_FACTORY), address(weth)), address(SWAP_ROUTER)
        );
        vm.label(address(SWAP_ROUTER), "SwapRouter");

        args = bytes.concat(
            abi.encode(
                address(leafVoter),
                metadexGaugeManager,
                votingRewardsFactory,
                address(POSITION_MANAGER),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this),
                address(this)
            ),
            abi.encode(uint128(type(uint128).max - 1), uint128(1), uint128(type(uint128).max - 1), MAX_MIN_STAKE_BLOCKS)
        );
        clGaugeFactory = ICLGaugeFactory(deployCode("out/CLGaugeFactory.sol/CLGaugeFactory.json", args));
        vm.label(address(clGaugeFactory), "CLGaugeFactory");

        vm.prank(metadexConfigAdmin);
        factoryRegistry.registerFactories(address(clGaugeFactory), address(CL_FACTORY));
    }

    /* //////////////////////////////////////////////////////////////
                              POOL MECHANICS
    ////////////////////////////////////////////////////////////// */

    function mockEarned(ICLGauge gauge, address account, uint256 earned) internal {
        vm.mockCall(
            address(gauge), abi.encodeWithSelector(IMetadexCLGauge.earned.selector, account), abi.encode(earned)
        );
        vm.mockCall(
            address(gauge),
            abi.encodeWithSelector(IMetadexCLGauge.deferredEmissions.selector, account),
            abi.encode(earned)
        );
    }

    function closePenaltyWindow(ICLGauge gauge) internal {
        vm.roll(vm.getBlockNumber() + clGaugeFactory.minStakeBlocks(address(gauge)));
    }

    function sqrtPriceX96(ICLPool pool) internal view returns (uint160 sqrtPrice) {
        (sqrtPrice,,,,,) = pool.slot0();
    }

    function currentTick(ICLPool pool) internal view returns (int24 tick) {
        (, tick,,,,) = pool.slot0();
    }

    function amountsRoundedDown(uint160 sqrtPrice, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPrice, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), liquidity
        );
    }

    function liquidityForAmounts(uint160 sqrtPrice, int24 tickLower, int24 tickUpper, uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice, TickMath.getSqrtPriceAtTick(tickLower), TickMath.getSqrtPriceAtTick(tickUpper), amount0, amount1
        );
    }

    function positionLiquidity(uint256 tokenId) internal view returns (uint128 liquidity) {
        liquidity = POSITION_MANAGER.positions(tokenId).liquidity;
    }

    function positionTicks(uint256 tokenId) internal view returns (int24 tickLower, int24 tickUpper) {
        INonfungiblePositionManager.Position memory position = POSITION_MANAGER.positions(tokenId);
        (tickLower, tickUpper) = (position.tickLower, position.tickUpper);
    }

    function positionOwed(uint256 tokenId) internal view returns (uint128 owed0, uint128 owed1) {
        INonfungiblePositionManager.Position memory position = POSITION_MANAGER.positions(tokenId);
        (owed0, owed1) = (position.tokensOwed0, position.tokensOwed1);
    }

    function positionFees(ICLPool pool, uint256 tokenId) internal view returns (uint256 fees0, uint256 fees1) {
        INonfungiblePositionManager.Position memory position = POSITION_MANAGER.positions(tokenId);
        (uint256 inside0, uint256 inside1) =
            IMetadexCLPool(address(pool)).getFeeGrowthInside(position.tickLower, position.tickUpper);
        unchecked {
            fees0 = position.tokensOwed0
                + FixedPointMathLib.fullMulDiv(
                    inside0 - position.feeGrowthInside0LastX128, position.liquidity, 1 << 128
                );
            fees1 = position.tokensOwed1
                + FixedPointMathLib.fullMulDiv(
                    inside1 - position.feeGrowthInside1LastX128, position.liquidity, 1 << 128
                );
        }
    }

    function mintPositionFor(
        ICLPool pool,
        address provider,
        address owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) internal returns (uint256 tokenId, uint128 minted) {
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(pool), tickLower, tickUpper, liquidity);
        (tokenId, minted) = mintPosition(pool, provider, tickLower, tickUpper, amount0, amount1);
        vm.prank(provider);
        IERC721(address(POSITION_MANAGER)).safeTransferFrom(provider, owner, tokenId);
    }

    function swapInPool(ICLPool pool, address trader, address tokenIn, address tokenOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        ERC20Mock(tokenIn).mint(trader, amountIn);

        vm.startPrank(trader);
        ERC20Mock(tokenIn).approve(address(SWAP_ROUTER), amountIn);
        amountOut = SWAP_ROUTER.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, pool.tickSpacing(), tokenOut),
                recipient: trader,
                deadline: vm.getBlockTimestamp(),
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
        vm.stopPrank();
    }

    function swapAsActor(
        ICLPool pool,
        address actor,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint160 sqrtPriceLimit
    ) internal {
        vm.startPrank(actor);
        ERC20Mock(tokenIn).approve(address(SWAP_ROUTER), amountIn);
        SWAP_ROUTER.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                tickSpacing: pool.tickSpacing(),
                recipient: actor,
                deadline: vm.getBlockTimestamp(),
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: sqrtPriceLimit
            })
        );
        vm.stopPrank();
    }

    function tradeForTick(ICLPool pool, int24 tick)
        internal
        view
        returns (address tokenIn, address tokenOut, uint256 amountIn)
    {
        uint160 target = TickMath.getSqrtPriceAtTick(tick);
        uint160 spot = sqrtPriceX96(pool);
        bool zeroForOne = target < spot;

        amountIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(target, spot, pool.liquidity(), true)
            : SqrtPriceMath.getAmount1Delta(spot, target, pool.liquidity(), true);
        (tokenIn, tokenOut) = zeroForOne ? (pool.token0(), pool.token1()) : (pool.token1(), pool.token0());
    }

    function fundActorForTick(ICLPool pool, address actor, int24 tick) internal {
        (address tokenIn,, uint256 amountIn) = tradeForTick(pool, tick);
        ERC20Mock(tokenIn).mint(actor, amountIn);
    }

    function fundActorForPrice(ICLPool pool, address actor, uint160 target) internal returns (uint256 amountIn) {
        uint160 spot = sqrtPriceX96(pool);
        bool zeroForOne = target < spot;
        amountIn = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(target, spot, pool.liquidity(), true)
            : SqrtPriceMath.getAmount1Delta(spot, target, pool.liquidity(), true);
        ERC20Mock(zeroForOne ? pool.token0() : pool.token1()).mint(actor, amountIn);
    }

    function pushPriceToTick(ICLPool pool, address actor, int24 tick) internal {
        (address tokenIn, address tokenOut, uint256 amountIn) = tradeForTick(pool, tick);
        swapAsActor(pool, actor, tokenIn, tokenOut, amountIn, TickMath.getSqrtPriceAtTick(tick));
    }

    function parkAtTick(ICLPool pool, address actor, int24 tick) internal {
        (address tokenIn, address tokenOut, uint256 amountIn) = tradeForTick(pool, tick);
        amountIn = FixedPointMathLib.fullMulDivUp(amountIn, 1e6, 1e6 - pool.fee());
        if (amountIn == 0) return;
        ERC20Mock(tokenIn).mint(actor, amountIn);
        swapAsActor(pool, actor, tokenIn, tokenOut, amountIn, TickMath.getSqrtPriceAtTick(tick));
    }

    function pushPrice(ICLPool pool, address actor, bool zeroForOne, uint256 amountIn) internal {
        (address tokenIn, address tokenOut) =
            zeroForOne ? (pool.token0(), pool.token1()) : (pool.token1(), pool.token0());
        swapAsActor(pool, actor, tokenIn, tokenOut, amountIn, priceLimit(zeroForOne));
    }

    function restorePrice(ICLPool pool, address actor, bool zeroForOne, uint160 sqrtPriceLimit) internal {
        (address tokenIn, address tokenOut) =
            zeroForOne ? (pool.token1(), pool.token0()) : (pool.token0(), pool.token1());
        swapAsActor(pool, actor, tokenIn, tokenOut, ERC20Mock(tokenIn).balanceOf(actor), sqrtPriceLimit);
    }

    function priceLimit(bool zeroForOne) internal pure returns (uint160 sqrtPriceLimit) {
        sqrtPriceLimit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function feeEarningTrade(ICLPool pool, uint128 rangeLiquidity, uint256 amountIn, bool zeroForOne)
        internal
        view
        returns (uint256 bounded)
    {
        uint128 liquidity = pool.liquidity();
        uint256 least;
        uint256 most;
        {
            uint160 spot = sqrtPriceX96(pool);
            int24 tick = currentTick(pool);
            int24 tickSpacing = pool.tickSpacing();
            uint160 near = TickMath.getSqrtPriceAtTick(zeroForOne ? tick - tickSpacing : tick + tickSpacing);
            uint160 far = TickMath.getSqrtPriceAtTick(zeroForOne ? tick - 10 * tickSpacing : tick + 10 * tickSpacing);
            least = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(near, spot, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(spot, near, liquidity, true);
            most = zeroForOne
                ? SqrtPriceMath.getAmount0Delta(far, spot, liquidity, true)
                : SqrtPriceMath.getAmount1Delta(spot, far, liquidity, true);
        }

        uint256 share = rangeLiquidity == 0 ? 1 : uint256(liquidity) / rangeLiquidity + 1;
        if (least < Constants.MAX_FUZZED_AMOUNT / share) least *= share;
        else least = Constants.MAX_FUZZED_AMOUNT;
        // The input whose fee grows a range of rangeLiquidity a wei within two steps, after the unstaked levy.
        uint256 earning =
            FixedPointMathLib.fullMulDivUp(5 * share + 2, 1e12, uint256(pool.fee()) * (1e6 - pool.unstakedFee()));
        least = FixedPointMathLib.min(FixedPointMathLib.max(least, earning), Constants.MAX_FUZZED_AMOUNT);
        if (most > Constants.MAX_FUZZED_AMOUNT) most = Constants.MAX_FUZZED_AMOUNT;
        if (most < least) most = least;

        bounded = bound(amountIn, least, most);
    }

    function swapStepTarget(ICLPool pool, int24 tickLower, int24 tickUpper, bool zeroForOne)
        internal
        view
        returns (uint160 sqrtPriceTarget)
    {
        int24 tick = currentTick(pool);
        int24 tickSpacing = pool.tickSpacing();
        int24 compressed = tick / tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) --compressed;
        int24 wordEdge =
            zeroForOne ? ((compressed >> 8) << 8) * tickSpacing : ((((compressed + 1) >> 8) << 8) + 255) * tickSpacing;
        int24 edge =
            zeroForOne ? (wordEdge > tickLower ? wordEdge : tickLower) : (wordEdge < tickUpper ? wordEdge : tickUpper);
        sqrtPriceTarget = TickMath.getSqrtPriceAtTick(edge);
    }

    function swapStepOut(ICLPool pool, uint256 amountIn, uint160 sqrtPriceTarget)
        internal
        view
        returns (uint256 amountOut)
    {
        (,, amountOut,) = SwapMath.computeSwapStep(
            sqrtPriceX96(pool), sqrtPriceTarget, pool.liquidity(), -SafeCastLib.toInt256(amountIn), pool.fee()
        );
    }

    function createRoute(address tokenIn, address middle, address tokenOut, address provider)
        internal
        returns (ICLPool first, ICLPool second)
    {
        first = createPool(tokenIn, middle, TICK_SPACING, SQRT_PRICE_ONE_X96, OBSERVATION_CARDINALITY);
        mintPosition(first, provider, ROUTE_TICK_LOWER, ROUTE_TICK_UPPER, ROUTE_LIQUIDITY);
        second = createPool(middle, tokenOut, TICK_SPACING, SQRT_PRICE_ONE_X96, OBSERVATION_CARDINALITY);
        mintPosition(second, provider, ROUTE_TICK_LOWER, ROUTE_TICK_UPPER, ROUTE_LIQUIDITY);
    }

    function routeCalldata(address tokenIn, address middle, address tokenOut, uint256 amountIn, address recipient)
        internal
        pure
        returns (bytes memory data)
    {
        data = abi.encodeCall(
            IMetadexSwapRouter.exactInput,
            IMetadexSwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, TICK_SPACING, middle, TICK_SPACING, tokenOut),
                recipient: recipient,
                deadline: type(uint256).max,
                amountIn: amountIn,
                amountOutMinimum: 0
            })
        );
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function createPool(
        address tokenA,
        address tokenB,
        int24 tickSpacing,
        uint160 sqrtPrice,
        uint16 observationCardinality
    ) internal returns (ICLPool pool) {
        (address tokenLower, address tokenUpper) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pool = ICLPool(CL_FACTORY.createPool(tokenLower, tokenUpper, tickSpacing, sqrtPrice));
        vm.label(address(pool), "CLPool");
        pool.increaseObservationCardinalityNext(observationCardinality);
    }

    function createGauge(ICLPool pool, bool activate) internal returns (ICLGauge gauge) {
        vm.startPrank(metadexGaugeManager);
        (address gaugeAddress, address emissions) = clGaugeFactory.createGauge(address(pool), "");
        factoryRegistry.registerGauge(gaugeAddress, address(clGaugeFactory), emissions, address(pool));
        leafVoter.registerGauge(gaugeAddress, activate);
        vm.stopPrank();
        gauge = ICLGauge(gaugeAddress);
    }

    function mintPosition(
        ICLPool pool,
        address provider,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256 tokenId, uint128 liquidity) {
        ERC20Mock(pool.token0()).mint(provider, amount0);
        ERC20Mock(pool.token1()).mint(provider, amount1);

        vm.startPrank(provider);
        ERC20Mock(pool.token0()).approve(address(POSITION_MANAGER), amount0);
        ERC20Mock(pool.token1()).approve(address(POSITION_MANAGER), amount1);
        (tokenId, liquidity,,) = POSITION_MANAGER.mint(
            INonfungiblePositionManager.MintParams({
                token0: pool.token0(),
                token1: pool.token1(),
                tickSpacing: pool.tickSpacing(),
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: 0,
                amount1Min: 0,
                recipient: provider,
                deadline: vm.getBlockTimestamp(),
                sqrtPriceX96: 0
            })
        );
        vm.stopPrank();
    }

    function mintPosition(ICLPool pool, address provider, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        returns (uint256 tokenId, uint128 liquidityMinted)
    {
        uint128 padded = uint128(FixedPointMathLib.min(uint256(liquidity) + liquidity / 1e12 + 2, type(uint128).max));
        (uint256 amount0, uint256 amount1) = amountsRoundedUp(sqrtPriceX96(pool), tickLower, tickUpper, padded);
        (tokenId, liquidityMinted) = mintPosition(pool, provider, tickLower, tickUpper, amount0, amount1);
        if (liquidityMinted < liquidity) revert MintShort();
    }

    function amountsRoundedUp(uint160 sqrtPrice, int24 tickLower, int24 tickUpper, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        uint160 sqrtPriceAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceBX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        if (sqrtPrice <= sqrtPriceAX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, true);
        } else if (sqrtPrice < sqrtPriceBX96) {
            amount0 = SqrtPriceMath.getAmount0Delta(sqrtPrice, sqrtPriceBX96, liquidity, true);
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPrice, liquidity, true);
        } else {
            amount1 = SqrtPriceMath.getAmount1Delta(sqrtPriceAX96, sqrtPriceBX96, liquidity, true);
        }
    }

    function stake(ICLGauge gauge, address owner, uint256 tokenId) internal {
        vm.startPrank(owner);
        POSITION_MANAGER.approve(address(gauge), tokenId);
        gauge.deposit(tokenId);
        vm.stopPrank();
    }

    function addEmissionsToGaugeCL(ICLPool pool, ICLGauge gauge, uint256 emissions) internal {
        addEmissionsToGauge(address(gauge), emissions);
        vm.prank(address(gauge));
        pool.settleToBlock();
    }

    function setPenaltyConfig(uint256 minStakeBlocks, uint256 penaltyRate) internal {
        clGaugeFactory.setPenaltyConfig(minStakeBlocks, penaltyRate);
    }

    function setMinStakeBlocks(ICLGauge gauge, uint256 minStakeBlocks) internal {
        clGaugeFactory.setMinStakeBlocks(address(gauge), minStakeBlocks);
    }

    function setReferralConfig(ICLGauge gauge, address referral, uint256 share) internal {
        clGaugeFactory.setReferralConfig(address(gauge), referral, share);
    }

    function earnedWithoutPenalty(ICLGauge gauge, address account, uint256[] memory tokenIds)
        internal
        returns (uint256 amount)
    {
        uint256 snapshot = vm.snapshotState();
        clGaugeFactory.setPenaltyConfig(clGaugeFactory.minStakeBlocks(address(gauge)), 0);
        amount = gauge.earned(account, tokenIds);
        vm.revertToState(snapshot);
    }

    function hiddenEmissions(ICLGauge gauge, address account, uint256[] memory tokenIds)
        internal
        returns (uint256 amount)
    {
        amount = earnedWithoutPenalty(gauge, account, tokenIds) - gauge.earned(account, tokenIds);
    }

    function accrueForBlocks(ICLPool pool, ICLGauge gauge, uint256 blocks, uint256 emissions) internal {
        vm.roll(vm.getBlockNumber() + blocks);
        addEmissionsToGaugeCL(pool, gauge, emissions);
    }

    function setEmissionCap(ICLGauge gauge, uint128 cap) internal {
        clGaugeFactory.setEmissionCap(address(gauge), cap);
    }

    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128 maxLiquidity) {
        int24 minTick = TickMath.MIN_TICK - (TickMath.MIN_TICK % tickSpacing);
        int24 maxTick = TickMath.MAX_TICK - (TickMath.MAX_TICK % tickSpacing);
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing) + 1;
        maxLiquidity = type(uint128).max / numTicks;
    }
}

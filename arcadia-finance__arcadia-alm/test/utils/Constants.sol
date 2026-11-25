/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

library Constants {
    // The ceiling every fuzzed amount is bound to, what a TokenDelta component holds.
    uint256 internal constant MAX_FUZZED_AMOUNT = uint256(uint128(type(int128).max));
    // The upper end of the band every fuzzed pool price is drawn from.
    uint160 internal constant BOUND_SQRT_PRICE_UPPER = type(uint120).max;
    // The floor every fuzzed range liquidity is drawn from.
    uint128 internal constant MIN_FUZZED_LIQUIDITY = 1e6;
    // The ceiling every fuzzed emission amount is drawn from, a large share of the AERO supply for one gauge.
    uint256 internal constant MAX_EMISSIONS = 1e26;
    // The most values a solady AddressSet keeps in its root slots, where a removal keeps the order.
    uint256 internal constant MAX_INLINE_SET_LENGTH = 3;
    // The value a solady AddressSet reserves as its zero sentinel and refuses to hold.
    address internal constant SET_ZERO_SENTINEL = 0x0000000000000000000000fbb67FDa52D4Bfb8Bf;

    // The plan opcodes in the order of the command spec table.
    bytes internal constant OPCODES = hex"000102031011121314202130313233";

    // The value per share a plan may lose while a test is not testing that bound.
    uint16 internal constant WIDE_MAX_SHORTFALL_BPS = 10_000;
    // The TWAP window every core is configured with.
    uint32 internal constant TWAP_WINDOW = 300;
    // The 1e18-scaled deviation band every core is configured with.
    uint256 internal constant WIDE_DEVIATION = 1e18;
    // The widest 1e18-scaled band between a trusted price and the TWAP that storage holds.
    uint256 internal constant OPEN_TWAP_DEVIATION = type(uint64).max;
    // The aLP a seed locks.
    uint256 internal constant DEAD_SHARES = 1e6;
    // The highest protocol fee, in basis points.
    uint16 internal constant MAX_FEE_BPS = 5000;
    // The token amounts a core is seeded with.
    uint256 internal constant SEED_AMOUNT = 1e18;
    // The slippage the tests push the pool price within, in basis points.
    uint16 internal constant DEFAULT_SLIPPAGE_BPS = 100;
    // The gas every transaction pays before its first opcode.
    uint256 internal constant TX_BASE_GAS = 21_000;
    // The gas per calldata token outside the EIP-7623 floor.
    uint256 internal constant STANDARD_TOKEN_GAS = 4;
    // The gas per calldata token of the EIP-7623 floor.
    uint256 internal constant FLOOR_TOKEN_GAS = 10;

    // The band of ticks the library tests draw a range from.
    int24 internal constant BOUND_TICK = TickMath.MAX_TICK / 2;
    // The square root of 2^96.
    uint160 internal constant SQRT_Q96 = 1 << 48;
    // The highest swap fee a pool factory accepts, in pips.
    uint256 internal constant MAX_POOL_FEE = 100_000;
    // The highest unstaked fee a pool factory accepts, in pips.
    uint256 internal constant MAX_UNSTAKED_FEE = 500_000;
    // The ceiling of a fuzzed range's liquidity in the solver tests.
    uint128 internal constant MAX_RANGE_LIQUIDITY = 1 << 94;
    // The upper end of the band a fuzzed range price is drawn from in the solver tests.
    uint160 internal constant MAX_RANGE_SQRT_PRICE = 1 << 128;
    // The lower end of the band a fuzzed range price is drawn from in the solver tests.
    uint160 internal constant MIN_RANGE_SQRT_PRICE = 1 << 64;

    // The contract of a pool that is its synchronous vault over token0.
    uint8 internal constant CONTRACT_SYNC_VAULT0 = 0;
    // The contract of a pool that is its synchronous vault over token1.
    uint8 internal constant CONTRACT_SYNC_VAULT1 = 1;
    // The contract of a pool that is its asynchronous vault over token0.
    uint8 internal constant CONTRACT_ASYNC_VAULT0 = 2;
    // The contract of a pool that is its asynchronous vault over token1.
    uint8 internal constant CONTRACT_ASYNC_VAULT1 = 3;
    // The sync extension of every synchronous vault, created once.
    uint8 internal constant CONTRACT_SYNC_EXTENSION = 4;
    // The keeper extension of every core, created once.
    uint8 internal constant CONTRACT_KEEPER_EXTENSION = 5;
    // The admin extension of every core, created once.
    uint8 internal constant CONTRACT_ADMIN_EXTENSION = 6;
    // The contract of a pool that is its core.
    uint8 internal constant CONTRACT_CORE = 7;
    // Every contract of a pool but its core.
    uint8 internal constant CORE_DEPENDENCIES = 0x0f;
    // Every contract of a pool.
    uint8 internal constant ALL_CONTRACTS = 0x8f;
    // The extensions, created once for every pool.
    uint8 internal constant EXTENSION_CONTRACTS = 0x70;

    // The queue of token0 deposits a test may hold requests in.
    uint8 internal constant QUEUE_DEPOSIT0 = 0x01;
    // The queue of token1 deposits a test may hold requests in.
    uint8 internal constant QUEUE_DEPOSIT1 = 0x02;
    // The queue of token0 redeems a test may hold requests in.
    uint8 internal constant QUEUE_REDEEM0 = 0x04;
    // The queue of token1 redeems a test may hold requests in.
    uint8 internal constant QUEUE_REDEEM1 = 0x08;
    // Every queue.
    uint8 internal constant ALL_QUEUES = 0x0f;
    // The penalty window a Metadex CL gauge factory ships with, CLGaugeFactory.DEFAULT_MIN_STAKE_BLOCKS.
    uint256 internal constant METADEX_DEFAULT_MIN_STAKE_BLOCKS = 5;
    // The calldata tokens of a nonzero byte, a zero byte counting one, per EIP-7623.
    uint256 internal constant NONZERO_BYTE_TOKENS = 4;
    // The most observations a test grows a pool's oracle to, its slot writes within a 30M gas block.
    uint16 internal constant MAX_FUZZED_CARDINALITY = 1000;
    // The most controllers a test splits one request over, two orders of magnitude past one.
    uint256 internal constant MAX_FUZZED_CONTROLLERS = 100;
    // The slot solady leaves a reentrancy sentinel in when the guard is not transient.
    bytes32 internal constant FALLBACK_GUARD_SLOT = bytes32(uint256(0x8000000000ab143c06));
    // The slot solady's storage reentrancy guard keeps its sentinel in.
    bytes32 internal constant STORAGE_GUARD_SLOT = bytes32(uint256(0x929eee149b4bd21268));
    // The slot solady's ERC-20 keeps the total supply in.
    bytes32 internal constant TOTAL_SUPPLY_SLOT = bytes32(uint256(0x05345cdf77eb68f44c));
    // The canonical Permit2 address, which solady's ERC-20 grants an infinite allowance.
    address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    // The unit of a fee share, pips times basis points, Snapshot.getFeeShare.
    uint256 internal constant FEE_SHARE_UNIT = 1e10;
    // The compressed ticks one tick bitmap word holds, a bit each, TickBitmap.position.
    int24 internal constant BITMAP_WORD_TICKS = 256;
    // The least liquidity of the high half of a uint128, its top bit set.
    uint128 internal constant MIN_HIGH_LIQUIDITY = 1 << 127;
    // The sqrt price gap in the BOUND_TICK band where MIN_HIGH_LIQUIDITY moves 2+ wei.
    uint160 internal constant MIN_STEP_SQRT_PRICE_GAP = 1 << 40;
    // The lower end of the band a withdraw solver price is drawn from, the sqrt of a price of 2^-32.
    uint160 internal constant MIN_SOLVER_SQRT_PRICE = 1 << 80;
    // The upper end of the band a withdraw solver price is drawn from, the sqrt of a price of 2^32.
    uint160 internal constant MAX_SOLVER_SQRT_PRICE = 1 << 112;
    // The most ticks a range near spot spans in the withdraw solver tests, about a 10% price move.
    int24 internal constant MAX_NEAR_SPOT_TICKS = 1000;
    // The pips in a basis point, a pool fee's 1e6 denominator over ConfigLib.BPS_DENOMINATOR.
    uint256 internal constant PIPS_PER_BPS = 100;
    // The Arbitrum ArbSys precompile EmissionsLogic reads the block number from.
    address internal constant ARB_SYS = address(0x64);
    // The ticks below a price of one past which a range's token0 per liquidity passes one, 1.0001^-10_000 < 1/e.
    int24 internal constant WIDE_RANGE_TICKS = 20_000;

    // The least range liquidity of the deposit walk tests, their deposits inside the solver's 2^252 normalized cap.
    uint128 internal constant MIN_DEPOSIT_RANGE_LIQUIDITY = 1 << 90;
    // The fewest ticks the thin tokenOut range ends under the word start, a wei or more of token1 there.
    int24 internal constant MIN_THIN_EDGE_TICKS = 50;
    // The most ticks the thin tokenOut range ends under the word start, a few dozen wei of token1 there.
    int24 internal constant MAX_THIN_EDGE_TICKS = 100;
    // The most token1 the thin asset leg test holds idle or in a range below spot, a few wei.
    uint256 internal constant MAX_THIN_IDLE1 = 8;
    // The most multiple of the whole supply's tokenOut cost a max mint limit sits at, near enough to bind the buy.
    uint256 internal constant MAX_COST_MULTIPLE = 1e6;
    // The factor a mocked supply reads too small by, any of at least 2 pulling about that many times the quote.
    uint256 internal constant MOCKED_SUPPLY_DIVISOR = 8;
    // The part of the supply the sync mint tests bound shares to, a hundredth.
    uint256 internal constant MINT_SUPPLY_DIVISOR = 100;
    // The part of its fuzzed liquidity a range is seeded with, any above the deposit over it leaving room to grow.
    uint128 internal constant RANGE_ROOM_DIVISOR = 16;
    // The most supply of the tiny room deposit test, any supply working while its legs fit an amount.
    uint256 internal constant MAX_TINY_ROOM_SUPPLY = 1e9;
    // The least cap room of the tiny room deposit test, any working while its legs fit an amount.
    uint256 internal constant MIN_TINY_ROOM = 2;
    // The most cap room of the tiny room deposit test, any working while its legs fit an amount.
    uint256 internal constant MAX_TINY_ROOM = 100;
    // The part of the mint's rounding a price step moves in the dust leg tests, an eighth.
    uint256 internal constant PRICE_STEP_ROUNDING_DIVISOR = 8;
    // The part of an amount the pool fixture caps other providers' depth at, an eighth.
    uint256 internal constant POOL_DEPTH_DIVISOR = 8;
    // The most a settlement test holds, moves or counts in supply, 79 billion tokens of 18 decimals.
    uint256 internal constant MAX_SETTLEMENT_AMOUNT = type(uint96).max;
    // The most pool liquidity in the withdraw solver's proven domain, W <= L < 2^64.
    uint128 internal constant MAX_SOLVER_LIQUIDITY = type(uint64).max;
    // The most holdings B and A in the withdraw solver's proven domain, 2^64 tokens at 2^96.
    uint256 internal constant MAX_SOLVER_HOLDINGS = type(uint160).max;
    // The least range liquidity of the withdraw solver sale tests, 2^60 tokenOut a tick off spot, past its wei margins.
    uint128 internal constant MIN_SOLVER_RANGE_LIQUIDITY = 1 << 92;
    // The least pool liquidity of the withdraw solver step tests, a step's output past its wei roundings.
    uint128 internal constant MIN_SOLVER_STEP_LIQUIDITY = 1 << 40;
    // The most liquidity past the tick in the two step withdraw test, its token0 cost a uint64 idle at 2^-32.
    uint128 internal constant MAX_SOLVER_STEP_LIQUIDITY = 1 << 48;
}

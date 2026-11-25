/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic } from "../../src/core/libraries/logic/ALMCoreViewLogic.sol";
import { Base_Test } from "../Base.t.sol";
import { ERC20Mock } from "../utils/mocks/ERC20Mock.sol";
import { FixedPoint96 } from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";
import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";
import { PricedRange } from "../../src/vaults/types/PricedRange.sol";
import { STATE_SLOT } from "../../src/core/abstracts/storage/Storage.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all fuzz tests.
 */
// forge-lint: disable-next-item(unsafe-typecast)
abstract contract Fuzz_Test is Base_Test {
    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    struct RangeState {
        uint256 index;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint128 liquidityStaked;
        uint256 unstakedTokenId;
        uint256 stakedTokenId;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    ERC20Mock internal token0;
    ERC20Mock internal token1;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public virtual override {
        Base_Test.setUp();

        ERC20Mock tokenA = new ERC20Mock("Token A", "TKNA", 18);
        ERC20Mock tokenB = new ERC20Mock("Token B", "TKNB", 6);
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);
        vm.label(address(token0), "token0");
        vm.label(address(token1), "token1");
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function mockMaxSwapCostBps(address core, uint256 maxSwapCostBps) internal {
        // The core's plan bounds word, holding only the max swap cost.
        vm.mockCall(
            core,
            abi.encodeWithSignature(
                "extsload(bytes32)", bytes32(uint256(STATE_SLOT) + ALMCoreViewLogic.PLAN_BOUNDS_OFFSET)
            ),
            abi.encode(bytes32(maxSwapCostBps << ALMCoreViewLogic.MAX_SWAP_COST_BPS_SHIFT))
        );
    }

    function pricedOf(RangeState[] memory ranges) internal pure returns (PricedRange[] memory priced) {
        priced = new PricedRange[](ranges.length);
        for (uint256 i; i < ranges.length; ++i) {
            priced[i] = PricedRange({
                liquidity: ranges[i].liquidity + ranges[i].liquidityStaked,
                unstakedLiquidity: ranges[i].liquidity,
                sqrtPriceLowerX96: TickMath.getSqrtPriceAtTick(ranges[i].tickLower),
                sqrtPriceUpperX96: TickMath.getSqrtPriceAtTick(ranges[i].tickUpper)
            });
        }
    }

    function assertLeastAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 liquidity,
        uint256 amount0,
        uint256 amount1
    ) internal pure {
        // Each amount is the least the position manager's liquidity formula takes to reach the liquidity.
        uint160 spot =
            sqrtPriceX96 < sqrtPriceAX96 ? sqrtPriceAX96 : sqrtPriceX96 < sqrtPriceBX96 ? sqrtPriceX96 : sqrtPriceBX96;
        if (spot < sqrtPriceBX96) {
            uint256 intermediate = FullMath.mulDiv(spot, sqrtPriceBX96, FixedPoint96.Q96);
            assertGe(FullMath.mulDiv(amount0, intermediate, sqrtPriceBX96 - spot), liquidity);
            if (amount0 > 0) assertLt(FullMath.mulDiv(amount0 - 1, intermediate, sqrtPriceBX96 - spot), liquidity);
        } else {
            assertEq(amount0, 0);
        }
        if (spot > sqrtPriceAX96) {
            assertGe(FullMath.mulDiv(amount1, FixedPoint96.Q96, spot - sqrtPriceAX96), liquidity);
            if (amount1 > 0) assertLt(FullMath.mulDiv(amount1 - 1, FixedPoint96.Q96, spot - sqrtPriceAX96), liquidity);
        } else {
            assertEq(amount1, 0);
        }
    }
}

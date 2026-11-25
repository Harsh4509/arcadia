/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CommonBase } from "@forge-std/Base.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";
import { StdCheats } from "@forge-std/StdCheats.sol";
import { StdUtils } from "@forge-std/StdUtils.sol";
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @notice Common logic needed by all handler contracts.
 */
abstract contract BaseHandler is CommonBase, StdCheats, StdUtils {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // Base's block time, in seconds.
    uint256 internal constant BLOCK_TIME = 2;

    /* //////////////////////////////////////////////////////////////
                                VARIABLES
    ////////////////////////////////////////////////////////////// */

    mapping(bytes4 selector => uint256 count) public calls;
    mapping(bytes4 selector => uint256 count) public reverts;
    mapping(bytes4 selector => mapping(bytes4 reason => uint256 count)) public revertsByReason;

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier countCall(bytes4 selector) {
        calls[selector]++;
        _;
    }

    modifier advanceBlock() {
        vm.roll(vm.getBlockNumber() + 1);
        vm.warp(vm.getBlockTimestamp() + BLOCK_TIME);
        _;
        _afterAction();
    }

    /* //////////////////////////////////////////////////////////////
                             HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function _afterAction() internal virtual { }

    function _recordRevert(bytes4 selector, bytes memory reason) internal {
        reverts[selector]++;
        revertsByReason[selector][_selectorOf(reason)]++;
    }

    function _holdings(PricedRange[] memory ranges, uint160 sqrtPriceX96, uint256 idle0, uint256 idle1)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        (amount0, amount1) = (idle0, idle1);
        for (uint256 i; i < ranges.length; ++i) {
            (uint256 range0, uint256 range1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96, ranges[i].sqrtPriceLowerX96, ranges[i].sqrtPriceUpperX96, ranges[i].liquidity
            );
            (amount0, amount1) = (amount0 + range0, amount1 + range1);
        }
    }

    function _selectorOf(bytes memory reason) internal pure returns (bytes4 selector) {
        if (reason.length < 4) return bytes4(0);
        assembly {
            selector := mload(add(reason, 32))
        }
    }
}

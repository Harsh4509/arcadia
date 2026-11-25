/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { EquivalentPosition } from "../../../src/vaults/types/EquivalentPosition.sol";
import { EquivalentPositionMath } from "../../../src/vaults/libraries/math/EquivalentPositionMath.sol";
import { PricedRange } from "../../../src/vaults/types/PricedRange.sol";

contract EquivalentPositionMathExtension {
    PricedRange[] internal ranges;

    function pushRange(PricedRange memory range) external {
        ranges.push(range);
    }

    function getPosition(uint160 sqrtPriceX96, bool zeroForOne, uint256 idle0, uint256 idle1)
        external
        view
        returns (EquivalentPosition memory position)
    {
        position = EquivalentPositionMath.getPosition(ranges, sqrtPriceX96, zeroForOne, idle0, idle1);
    }

    function amountsAt(EquivalentPosition memory position, uint160 sqrtPriceX96, bool zeroForOne)
        external
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        (amountIn, amountOut) = EquivalentPositionMath.amountsAt(position, sqrtPriceX96, zeroForOne);
    }
}

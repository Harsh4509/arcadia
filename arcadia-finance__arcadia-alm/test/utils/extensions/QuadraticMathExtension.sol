/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { QuadraticMath } from "../../../src/vaults/libraries/math/QuadraticMath.sol";

contract QuadraticMathExtension {
    function getRoot(int256 a, int256 b, int256 c) external pure returns (uint256 x) {
        x = QuadraticMath.getRoot(a, b, c);
    }
}

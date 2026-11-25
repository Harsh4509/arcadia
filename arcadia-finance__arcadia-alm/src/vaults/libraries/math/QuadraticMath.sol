/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

// forge-lint: disable-next-item(unsafe-typecast)
library QuadraticMath {
    using FixedPointMathLib for uint256;

    /* //////////////////////////////////////////////////////////////
                              ROOT LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Calculates the smallest root of a * x² − b * x + c = 0, or one when it has no real root or c is at least b.
     * @param a The quadratic coefficient, nonnegative, with 192 binary precision.
     * @param b The linear coefficient, with 192 binary precision.
     * @param c The constant coefficient, with 192 binary precision.
     * @return x The root, zero when c is at most zero, with 192 binary precision.
     * @dev The smallest positive root is calculated as:
     *     x = 2c / (b + √[b² − 4ac])
     *     The alternative form (b − √[b² − 4ac]) / (2a) subtracts two numbers that are nearly equal when c is
     *     small, which causes a loss of precision. Adding them instead avoids that loss.
     * @dev The discriminant is taken relative to b², so b² is never calculated at full width:
     *     w = 4ac / b² = 4 * a * (c / b) / b
     *     √[b² − 4ac] = b * √[1 − w]
     *     => x = 2 * (c / b) / (1 + √[1 − w])
     * @dev 4ac ≥ b² counts as without a real root.
     */
    function getRoot(int256 a, int256 b, int256 c) internal pure returns (uint256 x) {
        // Without a positive c the root is zero, without a real root below one it is one.
        if (c <= 0) return 0;
        if (c >= b || uint256(a).fullMulDiv(uint256(c), uint256(b)) >= uint256(b) / 4) return 1 << 192;

        // Unchecked: c is below b and 4ac below b², so every term is at most 2^254.
        unchecked {
            // The discriminant and the root are both expressed in ratio = c / b.
            uint256 ratio = uint256(c).fullMulDivUnchecked(1 << 192, uint256(b)); // 192 binary precision.
            // 1 − w, with the discriminant w = 4 * a * (c / b) / b, 62 bits up as the sqrt halves the binary precision.
            uint256 radicand = ((1 << 192) - 4 * uint256(a).fullMulDivUnchecked(ratio, uint256(b))) << 62;
            // √[1 − w], rounded up so the root never exceeds the exact one.
            uint256 discriminantRoot = radicand.sqrt(); // 127 binary precision.
            if (discriminantRoot * discriminantRoot < radicand) ++discriminantRoot;

            // The smallest positive root, in the form that avoids the loss of precision: x = 2 * (c / b) / (1 + √[1 − w])
            x = (2 * ratio).fullMulDivUnchecked(1 << 127, (1 << 127) + discriminantRoot); // 192 binary precision.
        }
    }
}

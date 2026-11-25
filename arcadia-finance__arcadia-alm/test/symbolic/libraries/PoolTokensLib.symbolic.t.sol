/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { PoolTokens } from "../../../src/core/types/State.sol";
import { PoolTokensLibExtension } from "../../utils/extensions/PoolTokensLibExtension.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TokenDelta, TokenDeltaLib, toTokenDelta } from "../../../src/core/types/TokenDelta.sol";

/**
 * @notice Symbolic tests for the function "creditCollected" of library "PoolTokensLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract CreditCollected_PoolTokensLib_Symbolic_Test is Symbolic_Test {
    /* //////////////////////////////////////////////////////////////
                                 STRUCTS
    ////////////////////////////////////////////////////////////// */

    struct Split {
        uint256 protocolFees0;
        uint256 protocolFees1;
        int256 delta0;
        int256 delta1;
        int256 buffer0;
        int256 buffer1;
    }

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    PoolTokensLibExtension internal poolTokensLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        poolTokensLib = new PoolTokensLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                              HELPER FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    function splitOf(
        PoolTokens memory stored,
        uint16 protocolSwapFeeBps,
        int128 principal0,
        int128 principal1,
        uint128 fees0,
        uint128 fees1
    ) internal pure returns (Split memory split) {
        uint256 protocolFee0 = uint256(fees0) * protocolSwapFeeBps / 10_000;
        uint256 protocolFee1 = uint256(fees1) * protocolSwapFeeBps / 10_000;
        split.protocolFees0 = uint256(stored.protocolFees.amount0) + protocolFee0;
        split.protocolFees1 = uint256(stored.protocolFees.amount1) + protocolFee1;
        split.delta0 = int256(principal0) + int256(fees0 - protocolFee0);
        split.delta1 = int256(principal1) + int256(fees1 - protocolFee1);
        split.buffer0 = int256(uint256(stored.buffer.amount0)) + split.delta0;
        split.buffer1 = int256(uint256(stored.buffer.amount1)) + split.delta1;
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_creditCollected_SplitsTheFeesBetweenTheProtocolAndTheBuffer(
        PoolTokens memory stored,
        uint16 protocolSwapFeeBps,
        int128 principal0,
        int128 principal1,
        uint128 fees0,
        uint128 fees1
    ) public {
        // Given: Buffer and protocol fees, share <= half, principal and fees fit both.
        vm.assume(protocolSwapFeeBps <= 5000 && fees0 < 1 << 127 && fees1 < 1 << 127);
        Split memory split = splitOf(stored, protocolSwapFeeBps, principal0, principal1, fees0, fees1);
        vm.assume(split.delta0 <= type(int128).max && split.delta1 <= type(int128).max);
        vm.assume(split.buffer0 >= 0 && split.buffer0 <= int256(uint256(type(uint128).max)));
        vm.assume(split.buffer1 >= 0 && split.buffer1 <= int256(uint256(type(uint128).max)));
        vm.assume(split.protocolFees0 <= type(uint128).max && split.protocolFees1 <= type(uint128).max);
        poolTokensLib.setPoolTokens(
            stored.buffer.amount0, stored.buffer.amount1, stored.protocolFees.amount0, stored.protocolFees.amount1
        );
        poolTokensLib.setProtocolSwapFeeBps(protocolSwapFeeBps);

        // When: Applying the principal and the fees.
        TokenDelta delta = poolTokensLib.creditCollected(
            toTokenDelta(principal0, principal1), TokenDeltaLib.fromAmounts(fees0, fees1)
        );

        // Then: Protocol gets its floored fee share, the buffer the principal and rest.
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertEq(poolTokens.protocolFees.amount0, split.protocolFees0);
        assertEq(poolTokens.protocolFees.amount1, split.protocolFees1);
        assertEq(poolTokens.buffer.amount0, uint256(split.buffer0));
        assertEq(poolTokens.buffer.amount1, uint256(split.buffer1));
        assertEq(delta.amount0(), split.delta0);
        assertEq(delta.amount1(), split.delta1);
    }

    /// forge-config: default.symbolic.solver_command = "test/symbolic/tools/z3int.py -in"
    function prove_creditCollected_TheProtocolShareIsAtMostHalfOfTheFees(
        uint16 protocolSwapFeeBps,
        uint128 fees0,
        uint128 fees1
    ) public {
        // Given: A protocol share of at most half and fees that fit a delta.
        vm.assume(protocolSwapFeeBps <= 5000 && fees0 < 1 << 127 && fees1 < 1 << 127);
        poolTokensLib.setProtocolSwapFeeBps(protocolSwapFeeBps);

        // When: Applying the fees without a principal.
        poolTokensLib.creditCollected(toTokenDelta(0, 0), TokenDeltaLib.fromAmounts(fees0, fees1));

        // Then: Protocol fees are at most half of the fees, the buffer holds the rest.
        PoolTokens memory poolTokens = poolTokensLib.getPoolTokens();
        assertLe(2 * uint256(poolTokens.protocolFees.amount0), fees0);
        assertLe(2 * uint256(poolTokens.protocolFees.amount1), fees1);
        assertEq(uint256(poolTokens.buffer.amount0) + poolTokens.protocolFees.amount0, fees0);
        assertEq(uint256(poolTokens.buffer.amount1) + poolTokens.protocolFees.amount1, fees1);
    }
}

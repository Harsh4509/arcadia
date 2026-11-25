/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { SafeCastLib } from "@solady/utils/SafeCastLib.sol";
import { stdError } from "@forge-std/StdError.sol";
import { Symbolic_Test } from "../Symbolic.t.sol";
import { TokenAmounts, TokenDelta, TokenDeltaLib, toTokenDelta } from "../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLibExtension } from "../../utils/extensions/TokenDeltaLibExtension.sol";

/**
 * @notice Symbolic tests for the library "TokenDeltaLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract TokenDeltaLib_Symbolic_Test is Symbolic_Test {
    using TokenDeltaLib for TokenDelta;

    /* //////////////////////////////////////////////////////////////
                             TEST CONTRACTS
    ////////////////////////////////////////////////////////////// */

    TokenDeltaLibExtension internal tokenDeltaLib;

    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public {
        tokenDeltaLib = new TokenDeltaLibExtension();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function prove_add_SucceedsIffBothSumsFitInt128(int128 a0, int128 a1, int128 b0, int128 b1) public view {
        // Given: Any two deltas.
        int256 sum0 = int256(a0) + b0;
        int256 sum1 = int256(a1) + b1;
        bool fits = sum0 >= type(int128).min && sum0 <= type(int128).max && sum1 >= type(int128).min
            && sum1 <= type(int128).max;

        // When: Adding them.
        (bool success, bytes memory result) = address(tokenDeltaLib)
            .staticcall(abi.encodeCall(TokenDeltaLibExtension.add, (toTokenDelta(a0, a1), toTokenDelta(b0, b1))));

        // Then: It succeeds exactly when both sums fit, and returns them.
        assertEq(success, fits);
        if (success) {
            TokenDelta sum = abi.decode(result, (TokenDelta));
            assertEq(sum.amount0(), sum0);
            assertEq(sum.amount1(), sum1);
        } else {
            assertEq(result, abi.encodeWithSelector(SafeCastLib.Overflow.selector));
        }
    }

    function prove_neg_SucceedsIffNoComponentIsTheMinimum(int128 a0, int128 a1) public view {
        // Given: Any delta.
        bool fits = a0 != type(int128).min && a1 != type(int128).min;

        // When: Negating it.
        (bool success, bytes memory result) =
            address(tokenDeltaLib).staticcall(abi.encodeCall(TokenDeltaLibExtension.neg, (toTokenDelta(a0, a1))));

        // Then: It succeeds exactly when both negations fit, and returns them.
        assertEq(success, fits);
        if (success) {
            TokenDelta negated = abi.decode(result, (TokenDelta));
            assertEq(negated.amount0(), -int256(a0));
            assertEq(negated.amount1(), -int256(a1));
        } else {
            assertEq(result, abi.encodeWithSelector(SafeCastLib.Overflow.selector));
        }
    }

    function prove_fromAmounts_SucceedsIffBothAmountsAreBelow2To127(uint256 amount0, uint256 amount1) public view {
        // Given: Any two amounts.
        bool fits = amount0 < 1 << 127 && amount1 < 1 << 127;

        // When: Packing them.
        (bool success, bytes memory result) =
            address(tokenDeltaLib).staticcall(abi.encodeCall(TokenDeltaLibExtension.fromAmounts, (amount0, amount1)));

        // Then: It succeeds exactly when both fit in 127 bits.
        assertEq(success, fits);
        if (!success) assertEq(result, abi.encodeWithSelector(SafeCastLib.Overflow.selector));
    }

    function prove_fromAmounts_RoundTripsThroughToAmounts(uint256 amount0, uint256 amount1) public pure {
        // Given: Two amounts below 2^127.
        vm.assume(amount0 < 1 << 127 && amount1 < 1 << 127);

        // When: Packing them and reading them back.
        TokenDelta delta = TokenDeltaLib.fromAmounts(amount0, amount1);
        (uint256 read0, uint256 read1) = delta.toAmounts();

        // Then: Both come back, and the delta matches Uniswap's packing.
        assertEq(read0, amount0);
        assertEq(read1, amount1);
        assertEq(
            TokenDelta.unwrap(delta), TokenDelta.unwrap(toTokenDelta(int128(int256(amount0)), int128(int256(amount1))))
        );
    }

    function prove_toAmounts_ReadsBothComponentsSignExtended(int128 a0, int128 a1) public pure {
        // Given: Any delta.
        // When: Reading both components as amounts.
        (uint256 amount0, uint256 amount1) = toTokenDelta(a0, a1).toAmounts();

        // Then: Each is its component sign-extended to 256 bits.
        assertEq(amount0, uint256(int256(a0)));
        assertEq(amount1, uint256(int256(a1)));
    }

    function prove_applyDelta_SucceedsIffBothBalancesStayInUint128(
        uint128 amount0,
        uint128 amount1,
        int128 delta0,
        int128 delta1
    ) public {
        // Given: Any stored pair and any delta.
        tokenDeltaLib.setAmounts(amount0, amount1);
        int256 new0 = int256(uint256(amount0)) + delta0;
        int256 new1 = int256(uint256(amount1)) + delta1;
        bool fits = new0 >= 0 && new0 <= int256(uint256(type(uint128).max)) && new1 >= 0
            && new1 <= int256(uint256(type(uint128).max));

        // When: Applying the delta.
        (bool success, bytes memory result) = address(tokenDeltaLib)
            .call(abi.encodeCall(TokenDeltaLibExtension.applyDelta, (toTokenDelta(delta0, delta1))));

        // Then: Succeeds exactly when both balances stay in range, and stores the sums.
        assertEq(success, fits);
        if (success) {
            TokenAmounts memory amounts = tokenDeltaLib.getAmounts();
            assertEq(amounts.amount0, uint256(new0));
            assertEq(amounts.amount1, uint256(new1));
        } else {
            assertEq(result, stdError.arithmeticError);
        }
    }

    function prove_single_PacksTheAmountOnItsSideOnly(bool isToken0, int128 amount) public pure {
        // Given: Any signed amount of either token.
        // When: Packing it.
        TokenDelta delta = TokenDeltaLib.single(isToken0, amount);

        // Then: It is Uniswap's delta with the amount on its side and zero on the other.
        TokenDelta expected = isToken0 ? toTokenDelta(amount, 0) : toTokenDelta(0, amount);
        assertEq(TokenDelta.unwrap(delta), TokenDelta.unwrap(expected));
    }
}

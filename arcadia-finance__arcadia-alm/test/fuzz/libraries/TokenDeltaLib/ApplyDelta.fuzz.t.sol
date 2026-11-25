/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Constants } from "../../../utils/Constants.sol";
import { stdError } from "@forge-std/StdError.sol";
import { TokenAmounts, toTokenDelta } from "../../../../src/core/types/TokenDelta.sol";
import { TokenDeltaLib_Fuzz_Test } from "./_TokenDeltaLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "applyDelta" of library "TokenDeltaLib".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract ApplyDelta_TokenDeltaLib_Fuzz_Test is TokenDeltaLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_applyDelta_TakesMoreThanTheBalance_Token0(uint128 amount0, uint128 amount1, uint256 taken)
        public
    {
        // Given: A token0 balance short of what is taken out of it.
        amount0 = uint128(bound(amount0, 0, Constants.MAX_FUZZED_AMOUNT - 1));
        taken = bound(taken, uint256(amount0) + 1, Constants.MAX_FUZZED_AMOUNT + 1);
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a delta that takes more token0 than the balance holds.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        tokenDeltaLib.applyDelta(toTokenDelta(int128(-int256(taken)), 0));
    }

    function testFuzz_Revert_applyDelta_TakesMoreThanTheBalance_Token1(uint128 amount0, uint128 amount1, uint256 taken)
        public
    {
        // Given: A token1 balance short of what is taken out of it.
        amount1 = uint128(bound(amount1, 0, Constants.MAX_FUZZED_AMOUNT - 1));
        taken = bound(taken, uint256(amount1) + 1, Constants.MAX_FUZZED_AMOUNT + 1);
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a delta that takes more token1 than the balance holds.
        // Then: It reverts on the underflow.
        vm.expectRevert(stdError.arithmeticError);
        tokenDeltaLib.applyDelta(toTokenDelta(0, int128(-int256(taken))));
    }

    function testFuzz_Revert_applyDelta_CreditsPastUint128_Token0(uint128 amount0, uint128 amount1, uint128 credited)
        public
    {
        // Given: A token0 balance near enough the uint128 ceiling for a credit past it.
        amount0 = uint128(bound(amount0, Constants.MAX_FUZZED_AMOUNT + 2, type(uint128).max));
        credited = uint128(bound(credited, uint256(type(uint128).max - amount0) + 1, Constants.MAX_FUZZED_AMOUNT));
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a delta that credits token0 past the ceiling.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        tokenDeltaLib.applyDelta(toTokenDelta(int128(credited), 0));
    }

    function testFuzz_Revert_applyDelta_CreditsPastUint128_Token1(uint128 amount0, uint128 amount1, uint128 credited)
        public
    {
        // Given: A token1 balance near enough the uint128 ceiling for a credit past it.
        amount1 = uint128(bound(amount1, Constants.MAX_FUZZED_AMOUNT + 2, type(uint128).max));
        credited = uint128(bound(credited, uint256(type(uint128).max - amount1) + 1, Constants.MAX_FUZZED_AMOUNT));
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a delta that credits token1 past the ceiling.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        tokenDeltaLib.applyDelta(toTokenDelta(0, int128(credited)));
    }

    function testFuzz_Revert_applyDelta_CreditsPastUint128_BothAlike(uint128 amount, uint128 credited) public {
        // Given: Equal balances near enough the uint128 ceiling for a credit to pass it.
        amount = uint128(bound(amount, Constants.MAX_FUZZED_AMOUNT + 2, type(uint128).max));
        credited = uint128(bound(credited, uint256(type(uint128).max - amount) + 1, Constants.MAX_FUZZED_AMOUNT));
        tokenDeltaLib.setAmounts(amount, amount);

        // When: Applying a delta that credits both tokens past the ceiling alike.
        // Then: It reverts on the overflow.
        vm.expectRevert(stdError.arithmeticError);
        tokenDeltaLib.applyDelta(toTokenDelta(int128(credited), int128(credited)));
    }

    function testFuzz_Success_applyDelta_Credits(uint128 amount0, uint128 amount1, uint128 credited0, uint128 credited1)
        public
    {
        // Given: Balances with room for what is credited.
        credited0 = uint128(bound(credited0, 0, Constants.MAX_FUZZED_AMOUNT));
        credited1 = uint128(bound(credited1, 0, Constants.MAX_FUZZED_AMOUNT));
        amount0 = uint128(bound(amount0, 0, type(uint128).max - credited0));
        amount1 = uint128(bound(amount1, 0, type(uint128).max - credited1));
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a delta that credits both tokens.
        tokenDeltaLib.applyDelta(toTokenDelta(int128(credited0), int128(credited1)));

        // Then: Both balances grow by what was credited.
        TokenAmounts memory amounts = tokenDeltaLib.getAmounts();
        assertEq(amounts.amount0, uint256(amount0) + credited0);
        assertEq(amounts.amount1, uint256(amount1) + credited1);
    }

    function testFuzz_Success_applyDelta_Debits(uint128 amount0, uint128 amount1, uint256 taken0, uint256 taken1)
        public
    {
        // Given: Balances holding at least what is taken out of them.
        taken0 =
            bound(taken0, 0, amount0 < Constants.MAX_FUZZED_AMOUNT ? uint256(amount0) : Constants.MAX_FUZZED_AMOUNT);
        taken1 =
            bound(taken1, 0, amount1 < Constants.MAX_FUZZED_AMOUNT ? uint256(amount1) : Constants.MAX_FUZZED_AMOUNT);
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a delta that takes both tokens.
        tokenDeltaLib.applyDelta(toTokenDelta(int128(-int256(taken0)), int128(-int256(taken1))));

        // Then: Both balances shrink by what was taken.
        TokenAmounts memory amounts = tokenDeltaLib.getAmounts();
        assertEq(amounts.amount0, amount0 - taken0);
        assertEq(amounts.amount1, amount1 - taken1);
    }

    function testFuzz_Success_applyDelta_ZeroDeltaWritesNothing(uint128 amount0, uint128 amount1) public {
        // Given: Any balances.
        tokenDeltaLib.setAmounts(amount0, amount1);

        // When: Applying a zero delta.
        vm.record();
        tokenDeltaLib.applyDelta(toTokenDelta(0, 0));

        // Then: No storage is written, and the balances are unchanged.
        (, bytes32[] memory writes) = vm.accesses(address(tokenDeltaLib));
        assertEq(writes.length, 0);
        TokenAmounts memory amounts = tokenDeltaLib.getAmounts();
        assertEq(amounts.amount0, amount0);
        assertEq(amounts.amount1, amount1);
    }
}

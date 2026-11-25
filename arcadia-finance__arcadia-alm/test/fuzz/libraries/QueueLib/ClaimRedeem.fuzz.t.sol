/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { Claimable, PoolTokens } from "../../../../src/core/types/State.sol";
import { Constants } from "../../../utils/Constants.sol";
import { QueueLib } from "../../../../src/core/libraries/state/QueueLib.sol";
import { QueueLib_Fuzz_Test } from "./_QueueLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "claimRedeem" of library "QueueLib".
 */
contract ClaimRedeem_QueueLib_Fuzz_Test is QueueLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_claimRedeem_InsufficientClaimable(
        address vault,
        address controller,
        bool isToken0,
        uint256 shares,
        uint256 maxAssets
    ) public {
        // Given: A controller with nothing claimable.

        // When: Claiming.
        // Then: It reverts.
        vm.expectRevert(QueueLib.InsufficientClaimable.selector);
        queueLib.claimRedeem(vault, controller, isToken0, shares, maxAssets);
    }

    function testFuzz_Success_claimRedeem_TakesThePayoutFromEscrow(
        address vault,
        address controller,
        bool isToken0,
        Claimable memory claimable,
        uint256 shares,
        uint256 maxAssets,
        uint128 escrowed
    ) public {
        // Given: A controller with a claimable redeem a token delta holds, and no record.
        claimable.amountIn = uint128(bound(claimable.amountIn, 1, type(uint128).max));
        claimable.amountOut = uint128(bound(claimable.amountOut, 0, Constants.MAX_FUZZED_AMOUNT));
        queueLib.setClaimableRedeem(vault, controller, claimable);

        // And: The claimable output escrowed, and shares within the claimable input.
        escrowed = uint128(bound(escrowed, claimable.amountOut, type(uint128).max));
        queueLib.setEscrowed(isToken0 ? escrowed : 0, isToken0 ? 0 : escrowed);
        shares = bound(shares, 0, claimable.amountIn);

        // When: Paying the redeem.
        uint256 assets = queueLib.claimRedeem(vault, controller, isToken0, shares, maxAssets);

        // Then: The assets are the pro-rata output, capped.
        uint256 expected = shares * claimable.amountOut / claimable.amountIn;
        assertEq(assets, expected < maxAssets ? expected : maxAssets);

        // And: They leave the escrow of the vault's token.
        PoolTokens memory poolTokens = queueLib.getPoolTokens();
        assertEq(isToken0 ? poolTokens.escrowed.amount0 : poolTokens.escrowed.amount1, escrowed - assets);
    }
}

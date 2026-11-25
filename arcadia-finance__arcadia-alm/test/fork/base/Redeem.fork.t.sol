/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { Base_Fork_Test } from "./_Base.fork.t.sol";
import { CLMath } from "../../../src/shared/libraries/math/CLMath.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";

/**
 * @notice Fork tests for the function "redeem" of contract "ALMVaultSync", on Base.
 */
contract Redeem_Base_Fork_Test is Base_Fork_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFork_Success_redeem_RangeAroundSpot(uint256 shares, bool isToken0, uint256 maxSwapCostBps) public {
        // Given: A core worth 100k USDC of each token, in a range 20 spacings either side of spot.
        seedCore(CLMath.convert(sqrtPriceX96(pool), false, 100_000e6, false), 100_000e6);
        openRange(spacedTick(-20), spacedTick(20));
        setMaxSwapCost(maxSwapCostBps);

        // And: A redeem of one share up to the steward's maxRedeem.
        ALMVaultSync vault = isToken0 ? syncVault0 : syncVault1;
        shares = bound(shares, 1, IALMSyncExtension(address(vault)).maxRedeem(steward));
        uint256 preview = vault.previewRedeem(shares);

        // When: The steward redeems.
        vm.prank(steward);
        uint256 assets = vault.redeem(shares, steward, steward);

        // Then: It paid the preview.
        assertEq(assets, preview);
    }
}

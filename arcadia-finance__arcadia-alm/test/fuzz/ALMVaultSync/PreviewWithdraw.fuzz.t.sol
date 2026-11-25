/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultSync } from "../../../src/vaults/ALMVaultSync.sol";
import { ALMVaultSync_Fuzz_Test } from "./_ALMVaultSync.fuzz.t.sol";
import { IALMSyncExtension } from "../../../src/interfaces/IALMSyncExtension.sol";
import { ReentrancyLock } from "../../../src/shared/abstracts/mixins/ReentrancyLock.sol";

/**
 * @notice Fuzz tests for the function "previewWithdraw" of contract "ALMVaultSync".
 */
contract PreviewWithdraw_ALMVaultSync_Fuzz_Test is ALMVaultSync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultSync_Fuzz_Test) {
        ALMVaultSync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_previewWithdraw_CoreNotDeployed(PoolState memory poolState, bool isToken0, uint256 assets)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? 0 : 1];

        // When: Reading previewWithdraw() on one of its synchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultSync(vault).previewWithdraw(assets);
    }

    function testFuzz_Revert_previewWithdraw_Reentrancy(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range.
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));

        // And: The core's lock is held.
        almCore.lock_();

        // When: Previewing a withdraw.
        // Then: It reverts on the lock.
        vm.expectRevert(ReentrancyLock.Reentrancy.selector);
        vault.previewWithdraw(assets);
    }

    function testFuzz_Success_previewWithdraw_NoSharesPayWhenNotInitialized(
        PoolState memory poolState,
        uint256 assets,
        bool isToken0
    ) public {
        // Given: A vault over a core that was never seeded.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        ALMVaultSync vault = vaultFor(isToken0);

        // And: A withdraw of at least 1 wei.
        assets = bound(assets, 1, type(uint256).max);

        // When: Previewing a withdraw.
        // Then: It reverts, or no shares pay it.
        try vault.previewWithdraw(assets) returns (uint256 shares) {
            assertEq(shares, type(uint256).max);
        } catch { }
    }

    function testFuzz_Success_previewWithdraw_ARedeemOfItPaysAtLeastTheAssets(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 assets,
        bool isToken0,
        uint256 maxSwapCostBps
    ) public {
        // Given: A pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // And: A seeded vault holding a range, and a holder that approved it.
        givenValidRangeState(range, poolState, false);

        // And: A seed receiver holding aLP.
        givenValidCoreState(coreState, poolState, range, almCore.DEAD_SHARES_() + 1, 0, 0);
        ALMVaultSync vault = seededVault(coreState, range, isToken0);
        setMaxSwapCost(givenValidMaxSwapCost(maxSwapCostBps, poolState.fee));
        approveVault(users.steward, vault, type(uint256).max);

        // And: An asset amount of at most the holder's maxWithdraw.
        uint256 maxAssets = IALMSyncExtension(address(vault)).maxWithdraw(users.steward);
        // And: Where maxWithdraw is zero, a hole no bound expresses.
        vm.assume(maxAssets > 0);
        assets = bound(assets, 1, maxAssets);

        // When: Previewing a withdraw.
        uint256 quoted = vault.previewWithdraw(assets);

        // Then: A redeem of the quoted shares pays at least the assets.
        vm.prank(users.steward);
        assertGe(vault.redeem(quoted, users.steward, users.steward, 0), assets);
    }
}

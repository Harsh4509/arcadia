/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMVaultAsync } from "../../../src/vaults/ALMVaultAsync.sol";
import { ALMVaultAsync_Fuzz_Test } from "./_ALMVaultAsync.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";

/**
 * @notice Fuzz tests for the function "maxRedeem" of contract "ALMVaultAsync".
 */
contract MaxRedeem_ALMVaultAsync_Fuzz_Test is ALMVaultAsync_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMVaultAsync_Fuzz_Test) {
        ALMVaultAsync_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_maxRedeem_CoreNotDeployed(PoolState memory poolState, bool isToken0, address controller_)
        public
    {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        address[4] memory list = halfCreatedVaults();
        address vault = list[isToken0 ? Constants.CONTRACT_ASYNC_VAULT0 : Constants.CONTRACT_ASYNC_VAULT1];

        // When: Reading maxRedeem() on one of its asynchronous vaults.
        // Then: It reverts without data, the read of the core finding no code.
        vm.expectRevert(bytes(""));
        ALMVaultAsync(vault).maxRedeem(controller_);
    }

    function testFuzz_Success_maxRedeem_ZeroBeforeSettlement(
        PoolState memory poolState,
        address controller_,
        bool isToken0
    ) public {
        // Given: The vaults over a pool, with nothing settled.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);

        // When: Reading maxRedeem.
        // Then: It is zero.
        assertEq(asyncVaultFor(isToken0).maxRedeem(controller_), 0);
    }

    function testFuzz_Success_maxRedeem_IsTheClaimableSide(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;

        // When: Reading maxRedeem.
        // Then: It is the settled shares.
        assertEq(vault.maxRedeem(controller), claimableIn);
    }

    function testFuzz_Success_maxRedeem_UnaffectedByTheCoreLock(
        PoolState memory poolState,
        CoreState memory coreState,
        RangeState memory range,
        uint256 shares,
        bool isToken0
    ) public {
        // Given: A seeded core, and a redeem the keeper settled for the controller.
        givenValidPoolState(poolState);
        setPoolState(poolState, false);
        givenValidRangeState(range, poolState, false);
        givenValidCoreState(coreState, poolState, range, 0, 0, 0);
        setSeededState(coreState, range);
        ALMVaultAsync vault = asyncVaultFor(isToken0);
        setRedeemClaimable(poolState, range, isToken0, controller, shares);
        uint256 claimableIn = almCore.claimableRedeem(address(vault), controller).amountIn;

        // When: A router reads maxRedeem while a keeper plan holds the core's lock.
        (bool success, bytes memory result) =
            readDuringPlan(address(vault), abi.encodeCall(vault.maxRedeem, (controller)));

        // Then: It answers as it does outside the plan.
        assertTrue(success);
        assertEq(abi.decode(result, (uint256)), claimableIn);
    }
}

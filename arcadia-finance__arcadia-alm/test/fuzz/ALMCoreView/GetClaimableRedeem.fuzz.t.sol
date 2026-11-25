/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { BaseVault } from "../../../src/vaults/abstracts/base/BaseVault.sol";
import { Claimable } from "../../../src/core/types/State.sol";

/**
 * @notice Fuzz tests for the function "getClaimableRedeem" of contract "ALMCoreView".
 */
contract GetClaimableRedeem_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreView_Fuzz_Test) {
        ALMCoreView_Fuzz_Test.setUp();
        setSpotPoolState();
        deployCoreView();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_getClaimableRedeem_CoreNotValid(address notCore, address vault, address controller_)
        public
    {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getClaimableRedeem(notCore, vault, controller_);
    }

    function testFuzz_Revert_getClaimableRedeem_CoreNotValid_HalfCreated(address vault, address controller_) public {
        // Given: A pool whose creation stopped with its four vaults deployed and no core.
        address core = BaseVault(halfCreatedVaults()[0]).share();

        // When: Reading its core address through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getClaimableRedeem(core, vault, controller_);
    }

    function testFuzz_Success_getClaimableRedeem_IsTheControllersPile(
        address vault,
        address controller_,
        Claimable memory claimable
    ) public {
        // Given: A claimable pile, written through the accessor.
        almCore.setClaimableRedeem(vault, controller_, claimable);

        // When: Reading it through the lens.
        Claimable memory read = coreView.getClaimableRedeem(address(almCore), vault, controller_);

        // Then: Both halves read back.
        assertEq(read.amountIn, claimable.amountIn);
        assertEq(read.amountOut, claimable.amountOut);
    }
}

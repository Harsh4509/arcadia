/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ERC20Share } from "../../../src/core/abstracts/tokens/ERC20Share.sol";

/**
 * @notice Fuzz tests for the function "DOMAIN_SEPARATOR" of contract "ALMCore".
 */
contract DomainSeparator_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCore_Fuzz_Test) {
        ALMCore_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Revert_DOMAIN_SEPARATOR_NotSupported(address caller) public {
        // Given: A core as deployed.

        // When: Calling DOMAIN_SEPARATOR().
        // Then: It reverts, the core taking no signed approvals.
        vm.prank(caller);
        vm.expectRevert(ERC20Share.NotSupported.selector);
        almCore.DOMAIN_SEPARATOR();
    }
}

/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ERC20Share } from "../../../src/core/abstracts/tokens/ERC20Share.sol";

/**
 * @notice Fuzz tests for the function "nonces" of contract "ALMCore".
 */
contract Nonces_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_nonces_NotSupported(address owner_) public {
        // Given: A core as deployed.

        // When: Calling nonces().
        // Then: It reverts, the core taking no signed approvals.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        almCore.nonces(owner_);
    }
}

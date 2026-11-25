/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { ERC20Share } from "../../../src/core/abstracts/tokens/ERC20Share.sol";

/**
 * @notice Fuzz tests for the function "permit" of contract "ALMCore".
 */
contract Permit_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_permit_NotSupported(
        address owner_,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        // Given: A core as deployed.

        // When: Calling permit().
        // Then: It reverts, the core taking no signed approvals.
        vm.expectRevert(ERC20Share.NotSupported.selector);
        almCore.permit(owner_, spender, value, deadline, v, r, s);
    }
}

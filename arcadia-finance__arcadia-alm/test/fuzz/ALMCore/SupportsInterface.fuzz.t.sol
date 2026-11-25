/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { IERC165 } from "@forge-std/interfaces/IERC165.sol";
import { IERC7540Operator } from "@forge-std/interfaces/IERC7540.sol";
import { IERC7575Share } from "@forge-std/interfaces/IERC7575.sol";

/**
 * @notice Fuzz tests for the function "supportsInterface" of contract "ALMCore".
 */
contract SupportsInterface_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Success_supportsInterface_ERC165(address caller) public {
        // Given: The ERC-165 interface id.

        // When: Any caller calls supportsInterface().
        // Then: It is true.
        vm.prank(caller);
        assertTrue(almCore.supportsInterface(type(IERC165).interfaceId));
    }

    function testFuzz_Success_supportsInterface_ERC7575Share(address caller) public {
        // Given: The ERC-7575 share interface id.

        // When: Any caller calls supportsInterface().
        // Then: It is true.
        vm.prank(caller);
        assertTrue(almCore.supportsInterface(type(IERC7575Share).interfaceId));
    }

    function testFuzz_Success_supportsInterface_ERC7540Operator(address caller) public {
        // Given: The ERC-7540 operator interface id.

        // When: Any caller calls supportsInterface().
        // Then: It is false.
        vm.prank(caller);
        assertFalse(almCore.supportsInterface(type(IERC7540Operator).interfaceId));
    }

    function testFuzz_Success_supportsInterface_UnknownId(bytes4 interfaceId) public {
        // Given: An interface id that is none of the supported ones.
        vm.assume(interfaceId != type(IERC165).interfaceId);
        vm.assume(interfaceId != type(IERC7575Share).interfaceId);

        // When: Calling supportsInterface().
        // Then: It is false.
        assertFalse(almCore.supportsInterface(interfaceId));
    }

    function testFuzz_Success_supportsInterface_UnknownIdAboveTheShareId(uint32 id) public {
        // Given: An interface id above the ERC-7575 share interface id.
        id = uint32(bound(id, uint32(type(IERC7575Share).interfaceId) + 1, type(uint32).max));

        // When: Calling supportsInterface().
        // Then: It is false.
        assertFalse(almCore.supportsInterface(bytes4(id)));
    }
}

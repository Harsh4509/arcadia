/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ShareLib_Fuzz_Test } from "./_ShareLib.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isCapExempt" of library "ShareLib".
 */
contract IsCapExempt_ShareLib_Fuzz_Test is ShareLib_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isCapExempt_TheCore(bool exempt) public {
        // Given: The core, on the exempt list or not.
        shareLib.setCapExempt(address(shareLib), exempt);

        // When: Reading whether it is exempt.
        bool result = shareLib.isCapExempt(address(shareLib));

        // Then: It is.
        assertTrue(result);
    }

    function testFuzz_Success_isCapExempt_OnTheList(address account) public {
        // Given: An account on the exempt list.
        shareLib.setCapExempt(account, true);

        // When: Reading whether it is exempt.
        bool result = shareLib.isCapExempt(account);

        // Then: It is.
        assertTrue(result);
    }

    function testFuzz_Success_isCapExempt_NotOnTheList(address account) public {
        // Given: An account that is neither the core nor on the exempt list.
        vm.assume(account != address(shareLib));
        shareLib.setCapExempt(account, false);

        // When: Reading whether it is exempt.
        bool result = shareLib.isCapExempt(account);

        // Then: It is not.
        assertFalse(result);
    }
}

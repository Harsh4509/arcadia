/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreViewLogic_Fuzz_Test } from "./_ALMCoreViewLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isExempt" of library "ALMCoreViewLogic".
 */
contract IsExempt_ALMCoreViewLogic_Fuzz_Test is ALMCoreViewLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMCoreViewLogic_Fuzz_Test) {
        ALMCoreViewLogic_Fuzz_Test.setUp();
        setSpotPoolState();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isExempt_ReadsTheFlagUnderItsOwnKey(address account, address secondAccount, bool exempt)
        public
    {
        // Given: One account whose exemption governance set, and another account.
        vm.assume(account != secondAccount);
        vm.prank(factory);
        almCore.setCapExempt(account, exempt);

        // When: Reading both accounts.
        bool read = coreViewLogic.isExempt(address(almCore), account);
        bool second = coreViewLogic.isExempt(address(almCore), secondAccount);

        // Then: The flag reads back under the account's own key, the other's stays unset.
        assertEq(read, exempt);
        assertFalse(second);
    }

    function testFuzz_Success_isExempt_TheCoreItselfReadsUnset(uint256 shares) public {
        // Given: A core no exemption was stored for, holding aLP of its own.
        almCore.mintShares(address(almCore), bound(shares, 1, type(uint128).max));

        // When: Reading the core's own flag.
        bool read = coreViewLogic.isExempt(address(almCore), address(almCore));

        // Then: Only the stored flag is reported, which is unset.
        assertFalse(read);
    }
}

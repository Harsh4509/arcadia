/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCoreView } from "../../../src/periphery/ALMCoreView.sol";
import { ALMCoreView_Fuzz_Test } from "./_ALMCoreView.fuzz.t.sol";
import { Epoch } from "../../../src/core/types/State.sol";
import { STATE_SLOT } from "../../../src/core/abstracts/storage/Storage.sol";

/**
 * @notice Fuzz tests for the function "getRedeemEpoch" of contract "ALMCoreView".
 */
contract GetRedeemEpoch_ALMCoreView_Fuzz_Test is ALMCoreView_Fuzz_Test {
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

    function testFuzz_Revert_getRedeemEpoch_CoreNotValid(address notCore, address vault, uint32 id) public {
        // Given: An address the factory does not hold as a core.
        vm.assume(notCore != address(almCore));

        // When: Reading it through the lens.
        // Then: It reverts.
        vm.expectRevert(ALMCoreView.CoreNotValid.selector);
        coreView.getRedeemEpoch(notCore, vault, id);
    }

    function testFuzz_Success_getRedeemEpoch_ReadsTheStoredWord(address vault, uint32 id, Epoch memory epoch) public {
        // Given: A redeem epoch, stored in its word.
        bytes32 base = keccak256(abi.encode(vault, bytes32(uint256(STATE_SLOT) + 20)));
        bytes32 slot = keccak256(abi.encode(uint256(id), bytes32(uint256(base) + 5)));
        vm.store(address(almCore), slot, bytes32((uint256(epoch.amountOut) << 128) | epoch.amountIn));

        // When: Reading it through the lens.
        Epoch memory read = coreView.getRedeemEpoch(address(almCore), vault, id);

        // Then: Every field reads back.
        assertEq(read.amountIn, epoch.amountIn);
        assertEq(read.amountOut, epoch.amountOut);
    }
}

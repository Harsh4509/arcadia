/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { BaseCore } from "../../../src/core/abstracts/base/BaseCore.sol";

/**
 * @notice Fuzz tests for the function "onERC721Received" of contract "ALMCore".
 */
// forge-lint: disable-next-item(unused-return)
contract OnERC721Received_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Revert_onERC721Received_Unauthorized(
        address caller,
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public {
        // Given: A caller that is not the position manager.
        vm.assume(caller != address(POSITION_MANAGER));

        // When: It hands the core a token id.
        // Then: It reverts.
        vm.prank(caller);
        vm.expectRevert(BaseCore.Unauthorized.selector);
        almCore.onERC721Received(operator, from, tokenId, data);
    }

    function testFuzz_Success_onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        public
    {
        // Given: The position manager is the caller.

        // When: It hands the core a token id.
        vm.prank(address(POSITION_MANAGER));
        bytes4 selector = almCore.onERC721Received(operator, from, tokenId, data);

        // Then: The core answers with the receiver selector.
        assertEq(selector, almCore.onERC721Received.selector);
    }
}

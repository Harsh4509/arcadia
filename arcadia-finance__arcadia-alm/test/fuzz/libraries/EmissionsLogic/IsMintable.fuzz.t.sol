/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ILeafVoter } from "../../../utils/fixtures/metadex/interfaces/ILeafVoter.sol";
import { EmissionsLogic_Fuzz_Test } from "./_EmissionsLogic.fuzz.t.sol";

/**
 * @notice Fuzz tests for the function "isMintable" of library "EmissionsLogic".
 */
contract IsMintable_EmissionsLogic_Fuzz_Test is EmissionsLogic_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_isMintable_ActiveOrSunset(uint256 pick) public {
        // Given: The leaf shape is deployed, and the chain is Active or Sunset.
        deployMetadex(false);
        setMintableStatus(pick);

        // When: Checking mintability.
        // Then: It is mintable.
        assertTrue(emissionsLogic.isMintable(address(leafVoter)));
    }

    function testFuzz_Success_isMintable_PausedOrSuspended(uint256 pick) public {
        // Given: The leaf shape is deployed, and the chain is Paused or Suspended.
        deployMetadex(false);
        setNotMintableStatus(pick);

        // When: Checking mintability.
        // Then: It is not mintable.
        assertFalse(emissionsLogic.isMintable(address(leafVoter)));
    }

    function testFuzz_Success_isMintable_None(uint32 blocks) public {
        // Given: The leaf shape at a fuzzed block, with a voter that reports no status.
        deployMetadex(false);
        vm.roll(vm.getBlockNumber() + blocks);
        vm.mockCall(
            address(leafVoter),
            abi.encodeWithSelector(ILeafVoter.chainStatus.selector),
            abi.encode(uint8(ILeafVoter.ChainStatus.None))
        );

        // When: Checking mintability.
        // Then: It is not mintable.
        assertFalse(emissionsLogic.isMintable(address(leafVoter)));
    }
}

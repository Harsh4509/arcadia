/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMCore_Fuzz_Test } from "./_ALMCore.fuzz.t.sol";
import { Vaults } from "../../../src/core/types/Vaults.sol";

/**
 * @notice Fuzz tests for the function "vault" of contract "ALMCore".
 */
contract Vault_ALMCore_Fuzz_Test is ALMCore_Fuzz_Test {
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

    function testFuzz_Success_vault_TheSynchronousVaultOfEachToken(bool isToken0) public {
        // Given: One of its tokens.
        address asset = isToken0 ? address(token0) : address(token1);

        // When: Looking up the vault of that token.
        address vault_ = almCore.vault(asset);

        // Then: It is the factory's synchronous vault over that token.
        Vaults memory vaults_ = deployer.getVaults(address(almCore));
        assertEq(vault_, isToken0 ? vaults_.syncVault0 : vaults_.syncVault1);
    }

    function testFuzz_Success_vault_NoneForAnyOtherAsset(address asset) public {
        // Given: Any address but its two tokens.
        vm.assume(asset != address(token0) && asset != address(token1));

        // When: Looking up the vault of that address.
        address vault_ = almCore.vault(asset);

        // Then: There is none.
        assertEq(vault_, address(0));
    }
}

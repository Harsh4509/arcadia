/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { ALMFactory_Fuzz_Test } from "./_ALMFactory.fuzz.t.sol";
import { Constants } from "../../utils/Constants.sol";
import { VaultParameters } from "../../../src/vaults/types/VaultParameters.sol";

/**
 * @notice Fuzz tests for the function "vaultParameters" of contract "BaseFactory".
 */
// forge-lint: disable-next-item(unsafe-typecast)
contract VaultParameters_ALMFactory_Fuzz_Test is ALMFactory_Fuzz_Test {
    /* //////////////////////////////////////////////////////////////
                                  SETUP
    ////////////////////////////////////////////////////////////// */

    function setUp() public override(ALMFactory_Fuzz_Test) {
        ALMFactory_Fuzz_Test.setUp();
    }

    /* //////////////////////////////////////////////////////////////
                                  TESTS
    ////////////////////////////////////////////////////////////// */

    function testFuzz_Success_vaultParameters_ZeroOutsideACreationCall(PoolState memory poolState) public {
        // Given: A factory over a pool with depth at a fuzzed price.
        givenValidPoolState(poolState);
        setFactoryState(poolState);

        // When: Reading the vault parameters outside a creation call.
        VaultParameters memory params = almFactory.vaultParameters();

        // Then: Every field is zero.
        assertFalse(params.assetIsToken0);
        assertEq(params.core, address(0));
        assertEq(params.pool, address(0));
        assertEq(params.syncExtension, address(0));
    }

    function testFuzz_Success_vaultParameters_SyncVaultNamesTheSyncExtension(
        PoolState memory poolState,
        uint8 contract_
    ) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: One of the two synchronous vaults.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_SYNC_VAULT1));

        // When: Reading the vault parameters while it is created.
        VaultParameters memory params = almFactory.vaultParametersDuring_(address(pool), contract_);

        // Then: The sync extension is the one every pool shares, at its CREATE2 address.
        assertEq(params.syncExtension, almFactory.computeAddress(address(0), Constants.CONTRACT_SYNC_EXTENSION));
        assertEq(
            params.syncExtension,
            contractAddress(
                address(almFactory), address(0), Constants.CONTRACT_SYNC_EXTENSION, creationCodes().syncExtension
            )
        );

        // And: The rest of the parameters are those of the vault.
        assertEq(params.assetIsToken0, contract_ == Constants.CONTRACT_SYNC_VAULT0);
        assertEq(params.core, almFactory.computeAddress(address(pool), Constants.CONTRACT_CORE));
        assertEq(params.pool, address(pool));
    }

    function testFuzz_Success_vaultParameters_NoSyncExtensionForOtherContracts(
        PoolState memory poolState,
        uint8 contract_
    ) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: Any contract but the synchronous vaults.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_ASYNC_VAULT0, Constants.CONTRACT_CORE));

        // When: Reading the vault parameters while it is created.
        VaultParameters memory params = almFactory.vaultParametersDuring_(address(pool), contract_);

        // Then: No sync extension is named.
        assertEq(params.syncExtension, address(0));
    }

    function testFuzz_Success_vaultParameters_AssetIsToken0(PoolState memory poolState, uint8 contract_) public {
        // Given: A factory with the creation of a core over the pool open.
        givenValidPoolState(poolState);
        setFactoryState(poolState);
        setCoreStarted();

        // And: Any contract of the pool.
        contract_ = uint8(bound(contract_, Constants.CONTRACT_SYNC_VAULT0, Constants.CONTRACT_CORE));

        // When: Reading the vault parameters while it is created.
        VaultParameters memory params = almFactory.vaultParametersDuring_(address(pool), contract_);

        // Then: The asset is token0 for the two vaults over token0 only.
        assertEq(
            params.assetIsToken0,
            contract_ == Constants.CONTRACT_SYNC_VAULT0 || contract_ == Constants.CONTRACT_ASYNC_VAULT0
        );
    }
}

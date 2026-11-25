/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.0;

import { CoreParameters } from "../../../src/core/types/CoreParameters.sol";
import { VaultParameters } from "../../../src/vaults/types/VaultParameters.sol";

/**
 * @notice A deployer that hands whatever parameters it is given to the contract it creates.
 */
contract DeployerMock {
    CoreParameters internal coreParameters;
    VaultParameters internal vaultParameters_;

    function setParameters(CoreParameters memory params) external {
        coreParameters = params;
    }

    function setVaultParameters(VaultParameters memory params) external {
        vaultParameters_ = params;
    }

    function parameters() external view returns (CoreParameters memory params) {
        params = coreParameters;
    }

    function vaultParameters() external view returns (VaultParameters memory params) {
        params = vaultParameters_;
    }

    function deploy(bytes memory creationCode) external returns (address instance) {
        assembly ("memory-safe") {
            instance := create(0, add(creationCode, 0x20), mload(creationCode))
            if iszero(instance) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
        }
    }
}

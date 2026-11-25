/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title ERC-7575 Vault.
 * @author Pragma Labs
 * @notice The ERC-7575 vault views, which are the ERC-4626 ones without the ERC-20 methods.
 */
abstract contract ERC7575Vault is ERC165 {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // type(IERC7575).interfaceId
    bytes4 internal constant ERC7575_VAULT_INTERFACE_ID = 0x2f0a18c5;

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The token this vault takes and pays.
     * @return assetTokenAddress The asset.
     */
    function asset() external view virtual returns (address assetTokenAddress);

    /**
     * @notice The token this vault issues a claim on.
     * @return shareTokenAddress The share.
     */
    function share() external view virtual returns (address shareTokenAddress);

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool supported) {
        supported = interfaceId == ERC7575_VAULT_INTERFACE_ID || super.supportsInterface(interfaceId);
    }
}

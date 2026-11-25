/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { RewardCheckpoint } from "../mixins/RewardCheckpoint.sol";

/**
 * @title ERC-7575 Share.
 * @author Pragma Labs
 * @notice The ERC-7575 share token, which names the vault of each asset.
 */
abstract contract ERC7575Share is ERC165, RewardCheckpoint {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // type(IERC7575Share).interfaceId
    bytes4 internal constant ERC7575_SHARE_INTERFACE_ID = 0xf815c03d;

    /* //////////////////////////////////////////////////////////////
                                  VAULTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The Vault for a given asset.
     * @param asset The asset to look up.
     * @return vault_ The Vault for asset, address(0) if none.
     */
    function vault(address asset) external view returns (address vault_) {
        if (asset == TOKEN0) vault_ = SYNC_VAULT0;
        else if (asset == TOKEN1) vault_ = SYNC_VAULT1;
    }

    /* //////////////////////////////////////////////////////////////
                              ERC20 METADATA
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC20
     */
    function name() public view override returns (string memory name_) {
        name_ = _state().share.name;
    }

    /**
     * @inheritdoc ERC20
     */
    function symbol() public view override returns (string memory symbol_) {
        symbol_ = _state().share.symbol;
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC165
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool supported) {
        supported = interfaceId == ERC7575_SHARE_INTERFACE_ID || super.supportsInterface(interfaceId);
    }
}

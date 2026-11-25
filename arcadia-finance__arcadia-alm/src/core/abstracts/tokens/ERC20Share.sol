/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ERC20 } from "@solady/tokens/ERC20.sol";

/**
 * @title ERC-20 Share.
 * @author Pragma Labs
 * @notice The aLP's ERC-20 base with permit disabled.
 */
abstract contract ERC20Share is ERC20 {
    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error NotSupported();

    /* //////////////////////////////////////////////////////////////
                             ERC20 OVERRIDES
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC20
     */
    function nonces(address) public pure override returns (uint256) {
        revert NotSupported();
    }

    /**
     * @inheritdoc ERC20
     */
    function permit(address, address, uint256, uint256, uint8, bytes32, bytes32) public pure override {
        revert NotSupported();
    }

    /**
     * @inheritdoc ERC20
     */
    function DOMAIN_SEPARATOR() public pure override returns (bytes32) {
        revert NotSupported();
    }

    /**
     * @inheritdoc ERC20
     */
    function _givePermit2InfiniteAllowance() internal pure override returns (bool give) {
        give = false;
    }
}

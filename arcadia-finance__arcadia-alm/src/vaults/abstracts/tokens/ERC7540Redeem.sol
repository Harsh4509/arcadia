/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ERC7540Operator } from "./ERC7540Operator.sol";

/**
 * @title ERC-7540 Redeem.
 * @author Pragma Labs
 * @notice The ERC-7540 redeem request views, and the redeem previews an asynchronous vault reverts.
 */
abstract contract ERC7540Redeem is ERC7540Operator {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // type(IERC7540Redeem).interfaceId
    bytes4 internal constant ERC7540_REDEEM_INTERFACE_ID = 0x620ee8e4;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /* //////////////////////////////////////////////////////////////
                                REQUESTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The shares a request holds before a fill.
     * @param requestId The request id.
     * @param controller The account the request is held for.
     * @return pendingShares The shares.
     */
    function pendingRedeemRequest(uint256 requestId, address controller)
        external
        view
        virtual
        returns (uint256 pendingShares);

    /**
     * @notice The shares a fill left to claim the asset against.
     * @param requestId The request id.
     * @param controller The account the request is held for.
     * @return claimableShares The shares.
     */
    function claimableRedeemRequest(uint256 requestId, address controller)
        external
        view
        virtual
        returns (uint256 claimableShares);

    /* //////////////////////////////////////////////////////////////
                                PREVIEWS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Always reverts.
     * @return Never returned.
     */
    function previewWithdraw(uint256) external pure returns (uint256) {
        revert PreviewNotSupported();
    }

    /**
     * @notice Always reverts.
     * @return Never returned.
     */
    function previewRedeem(uint256) external pure returns (uint256) {
        revert PreviewNotSupported();
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC7540Operator
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool supported) {
        supported = interfaceId == ERC7540_REDEEM_INTERFACE_ID || super.supportsInterface(interfaceId);
    }
}

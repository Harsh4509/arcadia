/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ERC7540Operator } from "./ERC7540Operator.sol";

/**
 * @title ERC-7540 Deposit.
 * @author Pragma Labs
 * @notice The ERC-7540 deposit request views, and the deposit previews an asynchronous vault reverts.
 */
abstract contract ERC7540Deposit is ERC7540Operator {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // type(IERC7540Deposit).interfaceId
    bytes4 internal constant ERC7540_DEPOSIT_INTERFACE_ID = 0xce3bbe50;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );

    /* //////////////////////////////////////////////////////////////
                                REQUESTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The asset amount a request holds before a fill.
     * @param requestId The request id.
     * @param controller The account the request is held for.
     * @return pendingAssets The asset amount.
     */
    function pendingDepositRequest(uint256 requestId, address controller)
        external
        view
        virtual
        returns (uint256 pendingAssets);

    /**
     * @notice The asset amount a fill left to claim the share against.
     * @param requestId The request id.
     * @param controller The account the request is held for.
     * @return claimableAssets The asset amount.
     */
    function claimableDepositRequest(uint256 requestId, address controller)
        external
        view
        virtual
        returns (uint256 claimableAssets);

    /* //////////////////////////////////////////////////////////////
                                PREVIEWS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Always reverts.
     * @return Never returned.
     */
    function previewDeposit(uint256) external pure returns (uint256) {
        revert PreviewNotSupported();
    }

    /**
     * @notice Always reverts.
     * @return Never returned.
     */
    function previewMint(uint256) external pure returns (uint256) {
        revert PreviewNotSupported();
    }

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC7540Operator
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool supported) {
        supported = interfaceId == ERC7540_DEPOSIT_INTERFACE_ID || super.supportsInterface(interfaceId);
    }
}

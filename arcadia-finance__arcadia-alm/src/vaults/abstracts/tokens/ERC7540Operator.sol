/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { ERC7575Vault } from "./ERC7575Vault.sol";

/**
 * @title ERC-7540 Operator.
 * @author Pragma Labs
 * @notice The ERC-7540 operator approvals of a vault.
 */
abstract contract ERC7540Operator is ERC7575Vault {
    /* //////////////////////////////////////////////////////////////
                                CONSTANTS
    ////////////////////////////////////////////////////////////// */

    // type(IERC7540Operator).interfaceId
    bytes4 internal constant ERC7540_OPERATOR_INTERFACE_ID = 0xe3bc4e65;

    /* //////////////////////////////////////////////////////////////
                                 EVENTS
    ////////////////////////////////////////////////////////////// */

    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error PreviewNotSupported();
    error Unauthorized();

    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Sets whether an operator may act for the caller.
     * @param operator The account approved to act on the caller's behalf.
     * @param approved True to approve, false to revoke.
     * @return success True.
     */
    function setOperator(address operator, bool approved) external returns (bool success) {
        _setOperator(msg.sender, operator, approved);
        success = true;

        emit OperatorSet(msg.sender, operator, approved);
    }

    /**
     * @notice Whether an operator may act for a controller.
     * @param controller The account the operator acts for.
     * @param operator The account acting.
     * @return status True when approved.
     */
    function isOperator(address controller, address operator) external view returns (bool status) {
        status = _isOperator(controller, operator);
    }

    /**
     * @notice Reverts unless the caller is the controller or an operator the controller approved.
     * @param controller The account acted for.
     */
    function _requireOperatorOrSelf(address controller) internal view {
        if (msg.sender != controller && !_isOperator(controller, msg.sender)) revert Unauthorized();
    }

    /**
     * @notice Sets the operator status of a controller.
     * @param controller The account the operator acts for.
     * @param operator The account acting.
     * @param approved True to approve, false to revoke.
     */
    function _setOperator(address controller, address operator, bool approved) internal virtual;

    /**
     * @notice Returns the operator status of a controller.
     * @param controller The account the operator acts for.
     * @param operator The account acting.
     * @return status True when approved.
     */
    function _isOperator(address controller, address operator) internal view virtual returns (bool status);

    /* //////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @inheritdoc ERC7575Vault
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool supported) {
        supported = interfaceId == ERC7540_OPERATOR_INTERFACE_ID || super.supportsInterface(interfaceId);
    }
}

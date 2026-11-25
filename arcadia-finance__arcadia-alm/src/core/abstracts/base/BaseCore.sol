/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { IALMCoreEvents } from "../../../interfaces/IALMCoreEvents.sol";
import { Immutables } from "../storage/Immutables.sol";
import { ReentrancyLock } from "../../../shared/abstracts/mixins/ReentrancyLock.sol";
import { Storage } from "../storage/Storage.sol";

/**
 * @title Base Core.
 * @author Pragma Labs
 * @notice The shared machinery of a core and its extensions.
 */
abstract contract BaseCore is Storage, Immutables, ReentrancyLock, IALMCoreEvents {
    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error InvalidRecipient();
    error Unauthorized();

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier onlyFactory() {
        _requireFactory();
        _;
    }

    /**
     * @notice Reverts unless the factory is calling.
     */
    function _requireFactory() internal view {
        if (msg.sender != FACTORY) revert Unauthorized();
    }
}

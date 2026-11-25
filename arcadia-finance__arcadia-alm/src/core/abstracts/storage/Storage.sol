/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

import { LibTransient } from "@solady/utils/LibTransient.sol";
import { State } from "../../types/State.sol";

// erc7201("arcadia.alm.core"), the slot of State.
bytes32 constant STATE_SLOT = 0xf337e37bd3891692fb524a02eedc850180dbc2332ff323439b5031c95d778600;
// erc7201("arcadia.alm.core.transient"), the transient slot of the emissions checkpoint flag.
bytes32 constant TRANSIENT_SLOT = 0x96a7a9e9ef75b4cd48bf368d0d27d3096ea7692bbe6eb8f0f0dcd3bdff116000;

/**
 * @title Storage.
 * @author Pragma Labs
 * @notice The storage location of a core.
 */
abstract contract Storage {
    /* //////////////////////////////////////////////////////////////
                                  SLOTS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice The core's state at its ERC-7201 slot.
     * @return state The state.
     */
    function _state() internal pure returns (State storage state) {
        assembly ("memory-safe") {
            state.slot := STATE_SLOT
        }
    }

    /**
     * @notice The execution's emissions checkpoint flag at its ERC-7201 transient slot.
     * @return checkpointed The transient flag.
     */
    function _checkpointed() internal pure returns (LibTransient.TBool storage checkpointed) {
        checkpointed = LibTransient.tBool(TRANSIENT_SLOT);
    }
}

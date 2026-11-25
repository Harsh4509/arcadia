/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

/**
 * @title Command Logic.
 * @author Pragma Labs
 * @notice The one-byte opcodes of a keeper plan, the high nibble their kind, the clear and cancel steps first.
 */
library CommandLogic {
    /* //////////////////////////////////////////////////////////////
                           REQUESTS SETTLEMENT
    ////////////////////////////////////////////////////////////// */

    uint8 internal constant CLEAR_REQUESTS = 0x00;
    uint8 internal constant CLEAR_ALL_REQUESTS = 0x01;
    uint8 internal constant CANCEL_REQUESTS = 0x02;
    uint8 internal constant SETTLE_REQUESTS = 0x03;

    /* //////////////////////////////////////////////////////////////
                                 TEARDOWN
    ////////////////////////////////////////////////////////////// */

    uint8 internal constant CLOSE_RANGE = 0x10;
    uint8 internal constant DECREASE_LIQUIDITY = 0x11;
    uint8 internal constant COLLECT = 0x12;
    uint8 internal constant UNSTAKE = 0x13;
    uint8 internal constant EMERGENCY_UNSTAKE = 0x14;

    /* //////////////////////////////////////////////////////////////
                                   SWAPS
    ////////////////////////////////////////////////////////////// */

    uint8 internal constant SWAP_VIA_POOL = 0x20;
    uint8 internal constant SWAP_VIA_ROUTER = 0x21;

    /* //////////////////////////////////////////////////////////////
                                  BUILDUP
    ////////////////////////////////////////////////////////////// */

    uint8 internal constant OPEN_RANGE = 0x30;
    uint8 internal constant INCREASE_LIQUIDITY = 0x31;
    uint8 internal constant STAKE = 0x32;
    uint8 internal constant INCREASE_STAKED_LIQUIDITY = 0x33;

    /* //////////////////////////////////////////////////////////////
                                 PAUSING
    ////////////////////////////////////////////////////////////// */

    // One bit per step a paused core refuses.
    uint256 internal constant PAUSABLE = (uint256(1) << OPEN_RANGE) | (uint256(1) << INCREASE_LIQUIDITY)
        | (uint256(1) << STAKE) | (uint256(1) << INCREASE_STAKED_LIQUIDITY) | (uint256(1) << SWAP_VIA_POOL)
        | (uint256(1) << SWAP_VIA_ROUTER);

    /**
     * @notice Whether a paused core refuses a step.
     * @param command The opcode.
     * @return refused True when a paused core refuses the step.
     */
    function pausable(uint8 command) internal pure returns (bool refused) {
        refused = ((PAUSABLE >> command) & 1) == 1;
    }
}

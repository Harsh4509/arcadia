/**
 * Created by Pragma Labs
 * SPDX-License-Identifier: BUSL-1.1
 */
pragma solidity ^0.8.34;

// Solady's transient reentrancy guard slot.
uint256 constant GUARD_SLOT = 0x8000000000ab143c06;

/**
 * @title Reentrancy Lock.
 * @author Pragma Labs
 * @notice A transient reentrancy lock on solady's guard slot.
 */
abstract contract ReentrancyLock {
    /* //////////////////////////////////////////////////////////////
                                 ERRORS
    ////////////////////////////////////////////////////////////// */

    error Reentrancy();

    /* //////////////////////////////////////////////////////////////
                                MODIFIERS
    ////////////////////////////////////////////////////////////// */

    modifier nonReentrant() {
        _lock();
        _;
        _unlock();
    }

    /* //////////////////////////////////////////////////////////////
                                  LOGIC
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Takes the lock.
     */
    function _lock() internal {
        _requireUnlocked();
        assembly ("memory-safe") {
            tstore(GUARD_SLOT, address())
        }
    }

    /**
     * @notice Requires the lock to be free.
     */
    function _requireUnlocked() internal view {
        assembly ("memory-safe") {
            if tload(GUARD_SLOT) {
                mstore(0x00, 0xab143c06)
                revert(0x1c, 0x04)
            }
        }
    }

    /**
     * @notice Clears the lock.
     */
    function _unlock() internal {
        assembly ("memory-safe") {
            tstore(GUARD_SLOT, 0)
        }
    }
}

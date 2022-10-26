// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error Locked();

/// @dev A simple reentrancy lock.
abstract contract Lock {
    uint8 private unlocked = 1;
    
    modifier lock() {
        if (unlocked == 0) {
            revert Locked();
        }
        unlocked = 0;
        _;
        unlocked = 1;
    }
}
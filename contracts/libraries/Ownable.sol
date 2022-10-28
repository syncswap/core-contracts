// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error NotOwner();
error NotPendingOwner();

abstract contract Ownable {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        if (owner != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    function setPendingOwner(address newPendingOwner) external onlyOwner {
        pendingOwner = newPendingOwner;
    }

    function acceptOwnership() external {
        address _pendingOwner = pendingOwner;
        if (msg.sender != _pendingOwner) {
            revert NotPendingOwner();
        }
        _transferOwnership(_pendingOwner);
        delete pendingOwner;
    }

    function _transferOwnership(address newOwner) private {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
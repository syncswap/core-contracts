// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

abstract contract Ownable {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Not owner");
        _;
    }

    function setPendingOwner(address newPendingOwner) external onlyOwner {
        pendingOwner = newPendingOwner;
    }

    function acceptOwnership() external {
        address _pendingOwner = pendingOwner;
        require(msg.sender == _pendingOwner, "Not pending owner");
        owner = _pendingOwner;
        delete pendingOwner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) private {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
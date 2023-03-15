// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/master/IPoolMaster.sol";
import "../interfaces/master/IFeeRegistry.sol";

import "../libraries/Ownable.sol";

contract FeeRegistry is IFeeRegistry, Ownable {
    /// @dev The pool master.
    address public immutable master;

    /// @dev Whether a fee sender is whitelisted.
    mapping(address => bool) public isSenderWhitelisted;

    event SetSenderWhitelisted(address indexed sender, bool indexed isWhitelisted);

    constructor(address _master) {
        master = _master;
    }

    /// @dev Returns whether the address is a valid fee sender.
    function isFeeSender(address sender) external view override returns (bool) {
        return isSenderWhitelisted[sender] || IPoolMaster(master).isPool(sender);
    }

    /// @dev Whitelists a fee sender explicitly.
    function setSenderWhitelisted(address sender, bool isWhitelisted) external onlyOwner {
        require(sender != address(0), "Invalid address");
        require(isSenderWhitelisted[sender] != isWhitelisted, "Already set");
        isSenderWhitelisted[sender] = isWhitelisted;
        emit SetSenderWhitelisted(sender, isWhitelisted);
    }
}
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/master/IForwarderRegistry.sol";

import "../libraries/Ownable.sol";

/// @notice A simple registry for sender forwarder contracts (usually the routers).
contract ForwarderRegistry is IForwarderRegistry, Ownable {
    mapping(address => bool) private _isForwarder;

    event AddForwarder(address forwarder);
    event RemoveForwarder(address forwarder);

    function isForwarder(address forwarder) external view override returns (bool) {
        return _isForwarder[forwarder];
    }

    function addForwarder(address forwarder) external onlyOwner {
        require(forwarder != address(0), "Invalid address");
        require(!_isForwarder[forwarder], "Already added");
        _isForwarder[forwarder] = true;
        emit AddForwarder(forwarder);
    }

    function removeForwarder(address forwarder) external onlyOwner {
        require(_isForwarder[forwarder], "Not added");
        delete _isForwarder[forwarder];
        emit RemoveForwarder(forwarder);
    }
}
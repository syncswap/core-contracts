// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../interfaces/token/IERC20.sol";

import "../BasePoolFactory.sol";

import "./SyncSwapClassicPool.sol";

contract SyncSwapClassicPoolFactory is BasePoolFactory {
    constructor(address _master) BasePoolFactory(_master) {
    }

    function _deployPool(address token0, address token1) internal override returns (address pool) {
        // Perform sanity check for tokens.
        IERC20(token0).balanceOf(address(this));
        IERC20(token1).balanceOf(address(this));

        bytes memory deployData = abi.encode(master, token0, token1);
        cachedDeployData = deployData;

        bytes32 salt = keccak256(deployData);
        pool = address(new SyncSwapClassicPool{salt: salt}());
    }
}
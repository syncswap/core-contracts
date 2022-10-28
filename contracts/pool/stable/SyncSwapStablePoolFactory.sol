// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../interfaces/token/IERC20.sol";

import "../BasePoolFactory.sol";

import "./SyncSwapStablePool.sol";

contract SyncSwapStablePoolFactory is BasePoolFactory {
    constructor(address _master) BasePoolFactory(_master) {
    }

    function _deployPool(address token0, address token1) internal override returns (address pool) {
        uint token0PrecisionMultiplier = 10 ** (18 - IERC20(token0).decimals());
        uint token1PrecisionMultiplier = 10 ** (18 - IERC20(token1).decimals());

        bytes memory deployData = abi.encode(master, token0, token1, token0PrecisionMultiplier, token1PrecisionMultiplier);
        cachedDeployData = deployData;

        bytes32 salt = keccak256(deployData);
        pool = address(new SyncSwapStablePool{salt: salt}());
    }
}
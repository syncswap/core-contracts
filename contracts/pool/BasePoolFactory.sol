// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/factory/IBasePoolFactory.sol";
import "../interfaces/master/IPoolMaster.sol";

error InvalidTokens();

abstract contract BasePoolFactory is IBasePoolFactory {
    /// @dev The pool master that control fees and registry.
    address public immutable master;

    /// @dev Pools by its two pool tokens.
    mapping(address => mapping(address => address)) public override getPool;

    bytes internal cachedDeployData;

    constructor(address _master) {
        master = _master;
    }

    function getDeployData() external view override returns (bytes memory deployData) {
        deployData = cachedDeployData;
    }

    function getSwapFee(
        address pool,
        address sender,
        address tokenIn,
        address tokenOut,
        bytes calldata data
    ) external view override returns (uint24 swapFee) {
        swapFee = IPoolMaster(master).getSwapFee(pool, sender, tokenIn, tokenOut, data);
    }

    function createPool(bytes calldata data) external override returns (address pool) {
        (address tokenA, address tokenB) = abi.decode(data, (address, address));

        // Perform safety checks.
        if (tokenA == tokenB) {
            revert InvalidTokens();
        }

        // Sort tokens.
        if (tokenB < tokenA) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        if (tokenA == address(0)) {
            revert InvalidTokens();
        }

        // Underlying implementation to deploy the pools and register them.
        pool = _createPool(tokenA, tokenB);

        // Populate mapping in both directions.
        // Not necessary as existence of the master, but keep them for better compatibility.
        getPool[tokenA][tokenB] = pool;
        getPool[tokenB][tokenA] = pool;

        emit PoolCreated(tokenA, tokenB, pool);
    }

    function _createPool(address tokenA, address tokenB) internal virtual returns (address) {
    }
}
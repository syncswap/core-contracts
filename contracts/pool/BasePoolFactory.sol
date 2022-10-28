// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/factory/IBasePoolFactory.sol";
import "../interfaces/IPoolMaster.sol";

import "../libraries/Ownable.sol";

error NotPoolMaster();
error IdenticalTokens();
error PoolExists();
error InvalidFee();

abstract contract BasePoolFactory is IBasePoolFactory, Ownable {
    /// @dev The pool master.
    address public immutable master;

    mapping(address => mapping(address => address)) public override getPool;

    bytes internal cachedDeployData;

    constructor(address _master) {
        master = _master;
    }

    function getDeployData() external view override returns (bytes memory deployData) {
        deployData = cachedDeployData;
    }

    function getSwapFee(address pool) external view override returns (uint24 swapFee) {
        swapFee = IPoolMaster(master).getSwapFee(pool);
    }

    function createPool(bytes calldata data) external override returns (address pool) {
        if (msg.sender != master) {
            revert NotPoolMaster();
        }

        (address tokenA, address tokenB) = abi.decode(data, (address, address));
        if (tokenA == tokenB) {
            revert IdenticalTokens();
        }
        if (getPool[tokenA][tokenB] != address(0)) {
            revert PoolExists();
        }
        if (tokenB < tokenA) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        pool = _deployPool(tokenA, tokenB);

        getPool[tokenA][tokenB] = pool;
        getPool[tokenB][tokenA] = pool; // populate mapping in the reverse direction.

        emit PoolCreated(tokenA, tokenB, pool);
    }

    function _deployPool(address tokenA, address tokenB) internal virtual returns (address) {
    }
}
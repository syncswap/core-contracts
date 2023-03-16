// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/master/IPoolMaster.sol";
import "../interfaces/factory/IPoolFactory.sol";

import "../libraries/Ownable2Step.sol";

error NotWhitelistedFactory();
error PoolAlreadyExists();

/// @notice The pool master manages swap fees for pools, whitelist for factories,
/// protocol fee and pool registry.
///
/// It accepts pool registers from whitelisted factories, with the pool data on pool
/// creation, to enable querying of the existence or fees of a pool by address or config.
///
/// This contract provides a unified interface to query and manage fees across
/// different pool types, and a unique registry for all pools.
///
contract SyncSwapPoolMaster is IPoolMaster, Ownable2Step {

    /// @dev The vault that holds funds.
    address public immutable override vault;

    // Forwarder Registry

    /// @dev The registry of forwarder.
    address public forwarderRegistry;

    // Fees

    /// @dev The fee manager.
    address public override feeManager;

    // Factories

    /// @dev Whether an address is a factory.
    mapping(address => bool) public override isFactoryWhitelisted;

    // Pools

    /// @dev Whether an address is a pool.
    mapping(address => bool) public override isPool;

    /// @dev Pools by hash of its config.
    mapping(bytes32 => address) public override getPool;

    address[] public override pools;

    constructor(address _vault, address _forwarderRegistry, address _feeManager) {
        vault = _vault;
        forwarderRegistry = _forwarderRegistry;
        feeManager = _feeManager;
    }

    function poolsLength() external view override returns (uint) {
        return pools.length;
    }

    // Forwarder Registry

    function isForwarder(address forwarder) external view override returns (bool) {
        return IForwarderRegistry(forwarderRegistry).isForwarder(forwarder);
    }

    function setForwarderRegistry(address newForwarderRegistry) external override onlyOwner {
        forwarderRegistry = newForwarderRegistry;
        emit UpdateForwarderRegistry(newForwarderRegistry);
    }

    // Fees

    function getSwapFee(
        address pool,
        address sender,
        address tokenIn,
        address tokenOut,
        bytes calldata data
    ) external view override returns (uint24 fee) {
        fee = IFeeManager(feeManager).getSwapFee(pool, sender, tokenIn, tokenOut, data);
    }

    function getProtocolFee(address pool) external view override returns (uint24 fee) {
        fee = IFeeManager(feeManager).getProtocolFee(pool);
    }

    function getFeeRecipient() external view override returns (address recipient) {
        recipient = IFeeManager(feeManager).getFeeRecipient();
    }

    function setFeeManager(address newFeeManager) external override onlyOwner {
        feeManager = newFeeManager;
        emit UpdateFeeManager(newFeeManager);
    }

    // Factories

    function setFactoryWhitelisted(address factory, bool whitelisted) external override onlyOwner {
        require(factory != address(0), "Invalid factory");
        isFactoryWhitelisted[factory] = whitelisted;
        emit SetFactoryWhitelisted(factory, whitelisted);
    }

    // Pools

    /// @dev Create a pool with deployment data and, register it via the factory.
    function createPool(address factory, bytes calldata data) external override returns (address pool) {
        // The factory have to call `registerPool` to register the pool.
        // The pool whitelist is checked in `registerPool`.
        pool = IPoolFactory(factory).createPool(data);
    }

    /// @dev Register a pool to the mapping by its config. Can only be called by factories.
    function registerPool(address pool, uint16 poolType, bytes calldata data) external override {
        if (!isFactoryWhitelisted[msg.sender]) {
            revert NotWhitelistedFactory();
        }

        require(pool != address(0));

        // Double check to prevent duplicated pools.
        if (isPool[pool]) {
            revert PoolAlreadyExists();
        }

        // Encode and hash pool config to get the mapping key.
        bytes32 hash = keccak256(abi.encode(poolType, data));

        // Double check to prevent duplicated pools.
        if (getPool[hash] != address(0)) {
            revert PoolAlreadyExists();
        }

        // Set to mappings.
        getPool[hash] = pool;
        isPool[pool] = true;
        pools.push(pool);

        emit RegisterPool(msg.sender, pool, poolType, data);
    }
}
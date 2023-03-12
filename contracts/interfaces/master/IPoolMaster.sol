// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

import "./IFeeManager.sol";
import "./IForwarderRegistry.sol";

/// @dev The master contract to create pools and manage whitelisted factories.
/// Inheriting the fee manager interface to support fee queries.
interface IPoolMaster is IFeeManager, IForwarderRegistry {
    event SetFactoryWhitelisted(address indexed factory, bool whitelisted);

    event RegisterPool(
        address indexed factory,
        address indexed pool,
        uint16 indexed poolType,
        bytes data
    );

    event UpdateForwarderRegistry(address indexed newForwarderRegistry);

    event UpdateFeeManager(address indexed newFeeManager);

    function vault() external view returns (address);

    function feeManager() external view returns (address);

    function pools(uint) external view returns (address);

    function poolsLength() external view returns (uint);

    // Forwarder Registry
    function setForwarderRegistry(address) external;

    // Fees
    function setFeeManager(address) external;

    // Factories
    function isFactoryWhitelisted(address) external view returns (bool);

    function setFactoryWhitelisted(address factory, bool whitelisted) external;

    // Pools
    function isPool(address) external view returns (bool);

    function getPool(bytes32) external view returns (address);

    function createPool(address factory, bytes calldata data) external returns (address pool);

    function registerPool(address pool, uint16 poolType, bytes calldata data) external;
}
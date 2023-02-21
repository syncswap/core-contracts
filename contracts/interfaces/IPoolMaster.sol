// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @dev The master contract to control fees, create pools and manage whitelisted factories.
/// Management functions are omitted.
interface IPoolMaster {
    // Events
    event SetDefaultSwapFee(uint16 indexed poolType, uint24 defaultSwapFee);

    event SetCustomSwapFee(address indexed pool, uint24 customSwapFee);

    event SetProtocolFee(uint16 indexed poolType, uint24 protocolFee);

    event SetFeeRecipient(address indexed previousFeeRecipient, address indexed newFeeRecipient);

    event SetFactoryWhitelisted(address indexed factory, bool whitelisted);

    event RegisterPool(
        address indexed factory,
        address indexed pool,
        uint16 indexed poolType,
        bytes data
    );

    function vault() external view returns (address);

    // Fees
    function defaultSwapFee(uint16 poolType) external view returns (uint24);

    function customSwapFee(address pool) external view returns (uint24);

    function feeRecipient() external view returns (address);

    function protocolFee(uint16 poolType) external view returns (uint24);
    
    function getSwapFee(address pool) external view returns (uint24 swapFee);

    // Factories
    function isFactoryWhitelisted(address) external view returns (bool);

    // Pools
    function isPool(address) external view returns (bool);

    function getPool(bytes32) external view returns (address);

    function createPool(address factory, bytes calldata data) external returns (address pool);

    function registerPool(address pool, uint16 poolType, bytes calldata data) external;
}
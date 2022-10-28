// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPoolMaster {
    event SetDefaultSwapFee(uint16 indexed poolType, uint24 defaultSwapFee);
    event SetCustomSwapFee(address indexed pool, uint24 customSwapFee);
    event SetProtocolFee(uint16 indexed poolType, uint24 protocolFee);
    event SetFeeRecipient(address indexed previousFeeRecipient, address indexed newFeeRecipient);
    event SetFactoryWhitelisted(address indexed factory, bool whitelisted);
    event CreatePool(address indexed factory, address indexed pool, bytes data);

    function vault() external view returns (address);

    function defaultSwapFee(uint16 poolType) external view returns (uint24);
    function customSwapFee(address pool) external view returns (uint24);
    function feeRecipient() external view returns (address);
    function protocolFee(uint16 poolType) external view returns (uint24);

    function isPool(address) external view returns (bool);
    function isFactoryWhitelisted(address) external view returns (bool);

    function getSwapFee(address pool) external view returns (uint24 swapFee);

    function createPool(address factory, bytes calldata data) external returns (address pool);
}
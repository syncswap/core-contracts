// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @dev The manager contract to control fees.
/// Management functions are omitted.
interface IFeeManager {
    function defaultSwapFee(uint16 poolType) external view returns (uint24);

    function customSwapFee(address pool) external view returns (uint24);

    function feeRecipient() external view returns (address);

    function protocolFee(uint16 poolType) external view returns (uint24);
    
    function getSwapFee(address pool) external view returns (uint24 swapFee);
}
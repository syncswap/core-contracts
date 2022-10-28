// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

import './IPoolFactory.sol';

/// @notice Canonical factory to deploy pools and control over fees.
interface IBasePoolFactory is IPoolFactory {
    /*
    struct CustomSwapFee {
        bool exists;
        uint24 fee;
    }

    event UpdateDefaultSwapFee(uint24 fee);

    event UpdateCustomSwapFee(
        address indexed pool,
        bool exists,
        uint24 fee
    );
    */

    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address pool,
        uint poolCount
    );

    function registry() external view returns (address);

    //function vault() external view returns (address);

    //function defaultSwapFee() external view returns (uint24 fee);

    //function customSwapFee(address pool) external view returns (bool exists, uint24 fee);

    function getDeployData() external view returns (bytes memory deployData);

    /// @notice Returns recipient of protocol fee.
    /// @dev A non-zero fee recipient will enable protocol fee.
    //function feeRecipient() external view returns (address);

    /// @notice Returns denominator of protocol fee fraction.
    /// @dev If has fee recipient, will mint protocol fee equivalent to 1/(protocolFee) of the growth in sqrt(k).
    //function protocolFee() external view returns (uint24);

    /// @notice Gets a pool by pool tokens and pool type.
    function getPool(address tokenA, address tokenB) external view returns (address pool);

    /// @notice Whether an address is a pool.
    //function isPool(address) external view returns (bool);

    /// @notice Get a pool from all created pools by index.
    //function pools(uint) external view returns (address pool);

    /// @notice Returns count of all created pools.
    //function poolsLength() external view returns (uint);

    /// @notice Returns swap fee for a swap.
    /// @dev Swap fee is in 1e5 precision.
    //function getSwapFee(address pool) external view returns (uint24 fee);

    /// @notice Sets recipient of protocol fee.
    /// @dev Can only be called by owner.
    //function setFeeRecipient(address feeRecipient) external;

    /// @notice Sets denominator of protocol fee fraction.
    /// @dev Can only be called by owner.
    //function setProtocolFee(uint24 protocolFee) external;

    //function setDefaultSwapFee(uint24 fee) external;

    //function setCustomSwapFee(address pool, uint24 fee) external;

    //function removeCustomSwapFee(address pool) external;
}
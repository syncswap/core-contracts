// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @notice Canonical factory to deploy pools and control over fees.
interface ISyncSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, bool stable, address pair, uint pairCount);

    /// @notice Returns recipient of protocol fee.
    /// @dev A non-zero fee recipient will enable protocol fee.
    function feeRecipient() external view returns (address);

    /// @notice Returns denominator of protocol fee fraction.
    /// @dev If has fee recipient, will mint protocol fee equivalent to 1/(protocolFee) of the growth in sqrt(k).
    function protocolFee() external view returns (uint8);

    /// @notice Returns address of current swap fee provider.
    function swapFeeProvider() external view returns (address);

    /// @notice Gets a pool by pool tokens and pool type.
    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair);

    /// @notice Whether an address is a pool.
    function isPair(address) external view returns (bool);

    /// @notice Get a pool from all created pools by index.
    function allPairs(uint) external view returns (address pair);

    /// @notice Returns count of all created pools.
    function allPairsLength() external view returns (uint);

    /// @notice Returns swap fee for a swap.
    /// @dev Swap fee is in 1e6 precision.
    function getSwapFee(
        address pool,
        address sender,
        address from,
        uint amount0In,
        uint amount1In
    ) external view returns (uint24);

    /// @notice Notify swap fee provider of a swap and returns its swap fee.
    /// @dev Can only be called by pools. Swap fee is in 1e6 precision.
    function notifySwapFee(
        address pool,
        address sender,
        address from,
        uint amount0In,
        uint amount1In
    ) external returns (uint24);

    /// @notice Create a pool.
    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);

    /// @notice Sets recipient of protocol fee.
    /// @dev Can only be called by owner.
    function setFeeRecipient(address feeRecipient) external;

    /// @notice Sets denominator of protocol fee fraction.
    /// @dev Can only be called by owner.
    function setProtocolFee(uint8 protocolFee) external;

    /// @notice Sets swap fee provider.
    /// @dev Can only be called by owner.
    function setSwapFeeProvider(address swapFeeProvider) external;
}
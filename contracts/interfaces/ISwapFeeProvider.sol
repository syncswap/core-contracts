// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @notice Provides swap fee for different pools and swaps.
interface ISwapFeeProvider {
    /// @dev Returns swap fee for a swap using counterfactuals.
    /// Swap fee is in 1e6 precision.
    function getSwapFee(
        address pool,
        address sender,
        address from,
        uint amount0In,
        uint amount1In
    ) external view returns (uint24);

    /// @dev Notify a swap and returns its swap fee.
    /// Can only be called by pools. Swap fee is in 1e6 precision.
    function notifySwapFee(
        address pool,
        address sender,
        address from,
        uint amount0In,
        uint amount1In
    ) external returns (uint24);
}
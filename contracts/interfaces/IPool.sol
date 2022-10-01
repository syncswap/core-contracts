// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPool {
    /// @notice The factory that deployed the pool.
    function factory() external view returns (address);

    /// @notice The first of the two tokens of the pool, sorted by address.
    function token0() external view returns (address);

    /// @notice The second of the two tokens of the pool, sorted by address.
    function token1() external view returns (address);

    /// @notice Whether the pool is using stable invariant.
    function stable() external view returns (bool);

    function reserve0() external view returns (uint);

    function reserve1() external view returns (uint);

    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint reserve0, uint reserve1);
}
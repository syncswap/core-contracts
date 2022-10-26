// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

import "./IERC20Permit2.sol";

interface ISyncSwapPoolBack is IERC20Permit2 {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);

    function A() external view returns (uint);
    function token0PrecisionMultiplier() external view returns (uint);
    function token1PrecisionMultiplier() external view returns (uint);

    function reserve0() external view returns (uint);
    function reserve1() external view returns (uint);
    function invariantLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function burnSingle(address tokenOut, address to) external returns (uint amountOut);
    function swap(address tokenIn, address to) external returns (uint amountOut);
    function flashSwap(uint amountOut0, uint amountOut1, address to, bytes calldata data) external returns (uint amountIn0, uint amountIn1);

    function getReserves() external view returns (uint, uint);
    function getAmountOut(address tokenIn, uint amountIn) external view returns (uint finalAmountOut);
    function getAmountIn(address tokenOut, uint256 amountOut) external view returns (uint finalAmountIn);

    event Mint(
        address indexed sender,
        uint amount0,
        uint amount1,
        uint liquidity,
        address indexed to
    );
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        uint liquidity,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(
        uint reserve0,
        uint reserve1
    );
}
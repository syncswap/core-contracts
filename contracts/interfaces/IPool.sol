// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPool {
    struct TokenAmount {
        address token;
        uint amount;
    }

    function poolType() external view returns (uint16);

    function factory() external view returns (address);
    function vault() external view returns (address);

    function getAssets() external view returns (address[] memory assets);

    function mint(bytes calldata data) external returns (uint liquidity);

    function burn(bytes calldata data) external returns (TokenAmount[] memory amounts);
    function burnSingle(bytes calldata data) external returns (uint amountOut);

    function swap(bytes calldata data) external returns (uint amountOut);
    //function flashSwap(bytes calldata data) external returns (uint amountIn0, uint amountIn1);
}
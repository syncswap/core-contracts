// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPoolERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);

    function nonces(address owner) external view returns (uint);
    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function permit2(address owner, address spender, uint amount, uint deadline, bytes calldata signature) external;

    event Approval(address indexed owner, address indexed spender, uint amount);
    event Transfer(address indexed from, address indexed to, uint amount);
}
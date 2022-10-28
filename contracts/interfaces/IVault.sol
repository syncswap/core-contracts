// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IVault {
    function wETH() external view returns (address);

    function reserves(address token) external view returns (uint reserve);

    function balanceOf(address token, address owner) external view returns (uint balance);

    function deposit(address token, address to) external payable returns (uint amount);

    function receiveAndDeposit(address token, address to, uint amount) external payable;

    function transfer(address token, address to, uint amount) external;

    function withdraw(address token, address to, uint amount) external;
}
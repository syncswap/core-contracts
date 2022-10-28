// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

import "./IERC20.sol";

interface IERC20Permit is IERC20 {
    function nonces(address owner) external view returns (uint);
    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}
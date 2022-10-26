// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface ISyncSwapCallback {
    function syncSwapCallback(uint amount0In, uint amount1In, uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}
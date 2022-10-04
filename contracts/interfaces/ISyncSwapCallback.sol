// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface ISyncSwapCallback {
    function syncSwapCallback(address sender, uint amount0Out, uint amount1Out, bytes calldata data) external;
}
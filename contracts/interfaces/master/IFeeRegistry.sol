// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IFeeRegistry {
    function isFeeSender(address sender) external view returns (bool);
}
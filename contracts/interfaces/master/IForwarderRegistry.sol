// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IForwarderRegistry {
    function isForwarder(address forwarder) external view returns (bool);
}
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IStakingPool {
    function stake(uint amount, address onBehalf) external;
}
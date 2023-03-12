// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../libraries/ERC20Permit2.sol";

contract TestERC20Permit2 is ERC20Permit2 {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}
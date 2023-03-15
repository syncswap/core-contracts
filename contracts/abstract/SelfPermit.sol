// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

import "../interfaces/token/IERC20Permit2.sol";
import "../interfaces/token/IERC20PermitAllowed.sol";

abstract contract SelfPermit {
    function selfPermit(
        address token,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function selfPermitIfNecessary(
        address token,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        if (IERC20(token).allowance(msg.sender, address(this)) < value) {
            selfPermit(token, value, deadline, v, r, s);
        }
    }

    function selfPermitAllowed(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IERC20PermitAllowed(token).permit(msg.sender, address(this), nonce, expiry, true, v, r, s);
    }

    function selfPermitAllowedIfNecessary(
        address token,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        if (IERC20(token).allowance(msg.sender, address(this)) < type(uint256).max) {
            selfPermitAllowed(token, nonce, expiry, v, r, s);
        }
    }

    function selfPermit2(
        address token,
        uint value,
        uint deadline,
        bytes calldata signature
    ) public payable {
        IERC20Permit2(token).permit2(msg.sender, address(this), value, deadline, signature);
    }

    function selfPermit2IfNecessary(
        address token,
        uint value,
        uint deadline,
        bytes calldata signature
    ) external payable {
        if (IERC20(token).allowance(msg.sender, address(this)) < value) {
            selfPermit2(token, value, deadline, signature);
        }
    }
}
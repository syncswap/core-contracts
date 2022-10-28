// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IVault.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/token/IERC20.sol";

import "./libraries/Lock.sol";
import "./libraries/TransferHelper.sol";

contract SyncSwapVault is IVault, Lock {

    address private constant NATIVE_ETH = address(0);
    address public immutable override wETH;

    mapping(address => mapping(address => uint)) private balances;
    mapping(address => uint) public override reserves;

    constructor(address _wETH) {
        wETH = _wETH;
    }

    receive() external payable {
        // Deposit ETH via fallback if not from the wETH withdraw.
        if (msg.sender != wETH) {
            deposit(NATIVE_ETH, msg.sender);
        }
    }

    function balanceOf(address token, address owner) external view override returns (uint balance) {
        // Ensure the same `balances` as native ETH.
        if (token == wETH) {
            token = NATIVE_ETH;
        }

        return balances[token][owner];
    }

    function deposit(address token, address to) public payable override lock returns (uint amount) {
        if (token == NATIVE_ETH) {
            // Use `msg.value` as amount for native ETH.
            amount = msg.value;
        } else {
            //require(msg.value == 0);

            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                // Use balance as amount for wETH.
                amount = IERC20(wETH).balanceOf(address(this));

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            } else {
                // Derive real amount with balance and reserve for ERC20 tokens.
                amount = IERC20(token).balanceOf(address(this)) - reserves[token];
            }
        }

        // Increase token reserve.
        reserves[token] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `reserves` doesn't overflow.
            balances[token][to] += amount;
        }
    }

    function receiveAndDeposit(address token, address to, uint amount) external payable override lock {
        if (token == NATIVE_ETH) {
            require(amount == msg.value);
        } else {
            // Receive ERC20 tokens from sender.
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            }
        }

        // Increase token reserve.
        reserves[token] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `reserves` doesn't overflow.
            balances[token][to] += amount;
        }
    }

    function transfer(address token, address to, uint amount) external override lock {
        // Ensure the same `reserves` and `balances` as native ETH.
        if (token == wETH) {
            token = NATIVE_ETH;
        }

        // Decrease token balance for sender.
        balances[token][msg.sender] -= amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `balances` doesn't underflow.
            balances[token][to] += amount;
        }
    }

    function withdraw(address token, address to, uint amount) external override lock {
        if (token == NATIVE_ETH) {
            // Send native ETH to recipient.
            TransferHelper.safeTransferETH(to, amount);
        } else {
            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                // Wrap native ETH to wETH.
                IWETH(wETH).deposit{value: amount}();

                // Send wETH to recipient.
                IWETH(wETH).transfer(to, amount);
            } else {
                // Send ERC20 tokens to recipient.
                TransferHelper.safeTransfer(token, to, amount);
            }
        }

        // Decrease token balance for sender.
        balances[token][msg.sender] -= amount;

        // Decrease token reserve.
        unchecked {
            /// `reserves` cannot underflow if `balances` doesn't underflow.
            reserves[token] -= amount;
        }
    }
}
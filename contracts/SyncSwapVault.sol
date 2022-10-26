// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IVault.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Lock.sol";
import "./libraries/TransferHelper.sol";

contract SyncSwapVault is IVault, Lock {

    address private constant NATIVE_ETH = address(0);
    address public immutable wETH;

    mapping(address => mapping(address => uint)) private accountBalances;
    mapping(address => uint) public tokenReserves;

    constructor(address _wETH) {
        wETH = _wETH;
    }

    function balanceOf(address token, address owner) external view returns (uint balance) {
        // Ensure the same `accountBalances` as native ETH.
        if (token == wETH) {
            token == NATIVE_ETH;
        }

        return accountBalances[token][owner];
    }

    function deposit(address token, address to) external payable lock returns (uint amount) {
        if (token == NATIVE_ETH) {
            // Use `msg.value` as amount for native ETH.
            amount = msg.value;
        } else {
            //require(msg.value == 0);

            if (token == wETH) {
                // Ensure the same `tokenReserves` and `accountBalances` as native ETH.
                token = NATIVE_ETH;

                // Use balance as amount for wETH.
                amount = IERC20(wETH).balanceOf(address(this));

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            } else {
                // Derive real amount with balance and reserve for ERC20 tokens.
                amount = IERC20(token).balanceOf(address(this)) - tokenReserves[token];
            }
        }

        /*
        if (token == NATIVE_ETH) {
            amount = msg.value;

            // Handle native ETH by using wETH values.
            token = wETH;

            // Wrap native ETH to wETH.
            IWETH(wETH).deposit{value: amount}();
        } else {
            amount = IERC20(token).balanceOf(address(this)) - tokenReserves[token];
        }
        */

        // Increase token reserve.
        tokenReserves[token] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// @dev `accountBalances` cannot overflow if `tokenReserves` doesn't overflow.
            accountBalances[token][to] += amount;
        }
    }

    function receiveAndDeposit(address token, address to, uint amount) external payable lock {
        if (token == NATIVE_ETH) {
            require(amount == msg.value);
        } else {
            // Receive ERC20 tokens from sender.
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

            if (token == wETH) {
                // Ensure the same `tokenReserves` and `accountBalances` as native ETH.
                token = NATIVE_ETH;

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            }
        }

        // Increase token reserve.
        tokenReserves[token] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// @dev `accountBalances` cannot overflow if `tokenReserves` doesn't overflow.
            accountBalances[token][to] += amount;
        }
    }

    function transfer(address token, address to, uint amount) external lock {
        // Ensure the same `tokenReserves` and `accountBalances` as native ETH.
        if (token == wETH) {
            token = NATIVE_ETH;
        }

        // Decrease token balance for sender.
        accountBalances[token][msg.sender] -= amount;

        // Increase token balance for recipient.
        unchecked {
            /// @dev `accountBalances` cannot overflow if `accountBalances` doesn't underflow.
            accountBalances[token][to] += amount;
        }
    }

    function withdraw(address token, address to, uint amount) external lock {
        if (token == NATIVE_ETH) {
            // Send native ETH to recipient.
            TransferHelper.safeTransferETH(to, amount);
        } else {
            if (token == wETH) {
                // Ensure the same `tokenReserves` and `accountBalances` as native ETH.
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

        /*
        // Send tokens to recipient.
        if (token == NATIVE_ETH) {
            // Handle native ETH by using wETH values.
            token = wETH;

            // Unwrap wETH to native ETH.
            IWETH(wETH).withdraw(amount);

            TransferHelper.safeTransferETH(to, amount);
        } else {
            TransferHelper.safeTransfer(token, to, amount);
        }
        */

        // Decrease token balance for sender.
        accountBalances[token][msg.sender] -= amount;

        // Decrease token reserve.
        unchecked {
            /// @dev `tokenReserves` cannot underflow if `accountBalances` doesn't underflow.
            tokenReserves[token] -= amount;
        }
    }
}
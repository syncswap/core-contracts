// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/IWETH.sol";
import "../interfaces/token/IERC20.sol";

import "../libraries/ReentrancyGuard.sol";
import "../libraries/TransferHelper.sol";

import "./VaultFlashLoans.sol";

/// @notice The vault stores all tokens supporting internal transfers to save gas.
contract SyncSwapVault is VaultFlashLoans {

    address private constant NATIVE_ETH = address(0);
    address public immutable override wETH;

    mapping(address => mapping(address => uint)) private balances; // token -> account -> balance
    mapping(address => uint) public override reserves; // token -> reserve

    constructor(address _wETH) VaultFlashLoans(msg.sender) {
        wETH = _wETH;
    }

    receive() external payable {
        // Deposit ETH via fallback if not from the wETH withdraw.
        if (msg.sender != wETH) {
            deposit(NATIVE_ETH, msg.sender);
        }
    }

    function balanceOf(address token, address account) external view override returns (uint balance) {
        // Ensure the same `balances` as native ETH.
        if (token == wETH) {
            token = NATIVE_ETH;
        }

        return balances[token][account];
    }

    // Deposit

    function deposit(address token, address to) public payable override nonReentrant returns (uint amount) {
        if (token == NATIVE_ETH) {
            // Use `msg.value` as amount for native ETH.
            amount = msg.value;
        } else {
            require(msg.value == 0);

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

    function depositETH(address to) external payable override nonReentrant returns (uint amount) {
        // Use `msg.value` as amount for native ETH.
        amount = msg.value;

        // Increase token reserve.
        reserves[NATIVE_ETH] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `reserves` doesn't overflow.
            balances[NATIVE_ETH][to] += amount;
        }
    }

    // Transfer tokens from sender and deposit, requires approval.
    function transferAndDeposit(address token, address to, uint amount) external payable override nonReentrant returns (uint) {
        if (token == NATIVE_ETH) {
            require(amount == msg.value);
        } else {
            require(msg.value == 0);

            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                // Receive wETH from sender.
                IWETH(wETH).transferFrom(msg.sender, address(this), amount);

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            } else {
                // Receive ERC20 tokens from sender.
                TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

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

        return amount;
    }

    // Transfer

    function transfer(address token, address to, uint amount) external override nonReentrant {
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

    // Withdraw

    function _wrapAndTransferWETH(address to, uint amount) private {
        // Wrap native ETH to wETH.
        IWETH(wETH).deposit{value: amount}();

        // Send wETH to recipient.
        IWETH(wETH).transfer(to, amount);
    }

    function withdraw(address token, address to, uint amount) external override nonReentrant {
        if (token == NATIVE_ETH) {
            // Send native ETH to recipient.
            TransferHelper.safeTransferETH(to, amount);
        } else {
            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                _wrapAndTransferWETH(to, amount);
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

    // Withdraw with mode.
    // 0 = DEFAULT
    // 1 = UNWRAPPED
    // 2 = WRAPPED
    function withdrawAlternative(address token, address to, uint amount, uint8 mode) external override nonReentrant {
        if (token == NATIVE_ETH) {
            if (mode == 2) {
                _wrapAndTransferWETH(to, amount);
            } else {
                // Send native ETH to recipient.
                TransferHelper.safeTransferETH(to, amount);
            }
        } else {
            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                if (mode == 1) {
                    // Send native ETH to recipient.
                    TransferHelper.safeTransferETH(to, amount);
                } else {
                    _wrapAndTransferWETH(to, amount);
                }
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

    function withdrawETH(address to, uint amount) external override nonReentrant {
        // Send native ETH to recipient.
        TransferHelper.safeTransferETH(to, amount);

        // Decrease token balance for sender.
        balances[NATIVE_ETH][msg.sender] -= amount;

        // Decrease token reserve.
        unchecked {
            /// `reserves` cannot underflow if `balances` doesn't underflow.
            reserves[NATIVE_ETH] -= amount;
        }
    }
}
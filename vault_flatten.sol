// File contracts/interfaces/token/IERC20Base.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IERC20Base {
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    
    event Approval(address indexed owner, address indexed spender, uint amount);
    event Transfer(address indexed from, address indexed to, uint amount);
}


// File contracts/interfaces/token/IERC20.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IERC20 is IERC20Base {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}


// File contracts/interfaces/IVault.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IVault {
    function wETH() external view returns (address);

    function reserves(address token) external view returns (uint reserve);

    function balanceOf(address token, address owner) external view returns (uint balance);

    function deposit(address token, address to) external payable returns (uint amount);

    function depositETH(address to) external payable returns (uint amount);

    function transferAndDeposit(address token, address to, uint amount) external payable;

    function transfer(address token, address to, uint amount) external;

    function withdraw(address token, address to, uint amount) external;

    function withdrawAlternative(address token, address to, uint amount, uint8 mode) external;

    function withdrawETH(address to, uint amount) external;
}


// File contracts/interfaces/IWETH.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function withdraw(uint) external;
}


// File contracts/libraries/Lock.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error Locked();

/// @dev A simple reentrancy lock.
abstract contract Lock {
    uint8 private unlocked = 1;
    
    modifier lock() {
        if (unlocked == 0) {
            revert Locked();
        }
        unlocked = 0;
        _;
        unlocked = 1;
    }
}


// File contracts/libraries/TransferHelper.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error SafeApproveFailed();
error SafeTransferFailed();
error SafeTransferFromFailed();
error SafeTransferETHFailed();

/// @dev Helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true / false.
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes("approve(address,uint256)")));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));

        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeApproveFailed();
        }
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes("transfer(address,uint256)")));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));

        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed();
        }
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));

        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFromFailed();
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = to.call{value: value}(new bytes(0));

        if (!success) {
            revert SafeTransferETHFailed();
        }
    }
}


// File contracts/SyncSwapVault.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
/// @notice The vault stores all tokens supporting internal transfers to save gas.
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

    // Deposit

    function deposit(address token, address to) public payable override lock returns (uint amount) {
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

    function depositETH(address to) external payable override lock returns (uint amount) {
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
    function transferAndDeposit(address token, address to, uint amount) external payable override lock {
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
    }

    // Transfer

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

    // Withdraw

    function _wrapAndTransferWETH(address to, uint amount) private {
        // Wrap native ETH to wETH.
        IWETH(wETH).deposit{value: amount}();

        // Send wETH to recipient.
        IWETH(wETH).transfer(to, amount);
    }

    function withdraw(address token, address to, uint amount) external override lock {
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
    function withdrawAlternative(address token, address to, uint amount, uint8 mode) external override lock {
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

    function withdrawETH(address to, uint amount) external override lock {
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
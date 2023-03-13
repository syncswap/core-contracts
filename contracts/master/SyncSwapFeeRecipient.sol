// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/token/IERC20.sol";
import "../interfaces/master/IFeeRegistry.sol";
import "../interfaces/master/IFeeRecipient.sol";

import "../libraries/Ownable2Step.sol";
import "../libraries/TransferHelper.sol";

error InvalidFeeSender();

contract SyncSwapFeeRecipient is IFeeRecipient, Ownable2Step {

    uint public constant EPOCH_DURATION = 7 days;

    /// @dev The registry for fee senders.
    address public feeRegistry;

    /// @dev The epoch fees of each token.
    mapping(uint => mapping(address => uint)) public fees; // epoch => token => amount

    /// @dev The fees tokens in each epoch.
    mapping(uint => address[]) public feeTokens;

    /// @dev Whether the address is a fee distributor.
    mapping(address => bool) public isFeeDistributor;

    /// @dev The fee distributors.
    address[] public feeDistributors; // for inspection only

    event NotifyFees(address indexed sender, uint16 indexed feeType, address indexed token, uint amount, uint feeRate);
    event AddFeeDistributor(address indexed distributor);
    event RemoveFeeDistributor(address indexed distributor);
    event SetFeeRegistry(address indexed feeRegistry);

    constructor(address _feeRegistry) {
        feeRegistry = _feeRegistry;
    }

    function feeTokensLength(uint epoch) external view returns (uint) {
        return feeTokens[epoch].length;
    }

    function getEpochStart(uint ts) public pure returns (uint) {
        return ts - (ts % EPOCH_DURATION);
    }

    /// @dev Notifies the fee recipient after sent fees.
    function notifyFees(
        uint16 feeType,
        address token,
        uint amount,
        uint feeRate,
        bytes calldata /*data*/
    ) external {
        if (!IFeeRegistry(feeRegistry).isFeeSender(msg.sender)) {
            revert InvalidFeeSender();
        }

        uint epoch = getEpochStart(block.timestamp);
        uint epochTokenFees = fees[epoch][token];

        // Pushes new tokens to array.
        if (epochTokenFees == 0) {
            feeTokens[epoch].push(token);
        }

        // Updates epoch fees for the token.
        epochTokenFees += amount;
        fees[epoch][token] = epochTokenFees;

        emit NotifyFees(msg.sender, feeType, token, amount, feeRate);
    }

    /// @dev Distributes fees to the recipient.
    function distributeFees(address to, address[] calldata tokens, uint[] calldata amounts) external {
        require(isFeeDistributor[msg.sender] || msg.sender == owner(), "No perms");
        require(tokens.length == amounts.length, "Wrong length");

        uint n = tokens.length;
        address token; uint amount;

        for (uint i; i < n; ) {
            token = tokens[i];
            amount = amounts[i];

            if (token == address(0)) { // ETH
                if (amount == 0) {
                    amount = address(this).balance;
                }
                TransferHelper.safeTransferETH(to, amount);
            } else {
                if (amount == 0) {
                    amount = IERC20(token).balanceOf(address(this));
                }
                TransferHelper.safeTransfer(token, to, amount);
            }

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Adds a new fee distributor.
    function addFeeDistributor(address distributor) external onlyOwner {
        require(!isFeeDistributor[distributor], "Already set");
        isFeeDistributor[distributor] = true;
        feeDistributors.push(distributor);
        emit AddFeeDistributor(distributor);
    }

    /// @dev Removes a new fee distributor.
    function removeFeeDistributor(address distributor, bool updateArray) external onlyOwner {
        require(isFeeDistributor[distributor], "Not set");
        delete isFeeDistributor[distributor];
        if (updateArray) {
            uint n = feeDistributors.length;
            for (uint i; i < n; ) {
                if (feeDistributors[i] == distributor) {
                    feeDistributors[i] = feeDistributors[n - 1];
                    feeDistributors[n - 1] = distributor;
                    feeDistributors.pop();
                    break;
                }

                unchecked {
                    ++i;
                }
            }
        }
        emit RemoveFeeDistributor(distributor);
    }

    /// @dev Sets a new fee registry.
    function setFeeRegistry(address _feeRegistry) external onlyOwner {
        require(_feeRegistry != address(0), "Invalid address");
        feeRegistry = _feeRegistry;
        emit SetFeeRegistry(_feeRegistry);
    }

    function withdrawERC20(address token, address to, uint amount) external onlyOwner {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }
        TransferHelper.safeTransfer(token, to, amount);
    }

    function withdrawETH(address to, uint amount) external onlyOwner {
        if (amount == 0) {
            amount = address(this).balance;
        }
        TransferHelper.safeTransferETH(to, amount);
    }
}
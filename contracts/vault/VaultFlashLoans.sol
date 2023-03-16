// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/token/IERC20.sol";
import "../interfaces/master/IFeeRecipient.sol";
import "../interfaces/vault/IVault.sol";
import "../interfaces/vault/IFlashLoanRecipient.sol";

import "../libraries/Pausable.sol";
import "../libraries/ReentrancyGuard.sol";
import "../libraries/TransferHelper.sol";

/**
 * @dev Handles Flash Loans through the Vault. Calls the `receiveFlashLoan` hook on the flash loan recipient
 * contract, which implements the `IFlashLoanRecipient` interface.
 */
abstract contract VaultFlashLoans is IVault, ReentrancyGuard, Pausable {

    bytes32 public constant ERC3156_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @dev Absolute maximum fee percentages (1e18 = 100%, 1e16 = 1%).
    uint private constant _MAX_PROTOCOL_FLASH_LOAN_FEE_PERCENTAGE = 10e16; // 10%

    // All fee percentages are 18-decimal fixed point numbers.
    // The flash loan fee is charged whenever a flash loan occurs, as a percentage of the tokens lent.
    uint public override flashLoanFeePercentage = 5e14; // 0.05%

    address public flashLoanFeeRecipient;

    // Events
    event FlashLoanFeePercentageChanged(uint oldFlashLoanFeePercentage, uint newFlashLoanFeePercentage);

    constructor(address _flashLoanFeeRecipient) {
        require(
            _flashLoanFeeRecipient != address(0),
            "INVALID_FLASH_LOAN_FEE_RECIPIENT"
        );
        flashLoanFeeRecipient = _flashLoanFeeRecipient;
    }

    function setFlashLoanFeeRecipient(address _flashLoanFeeRecipient) external onlyOwner {
        require(
            _flashLoanFeeRecipient != address(0),
            "INVALID_FLASH_LOAN_FEE_RECIPIENT"
        );
        flashLoanFeeRecipient = _flashLoanFeeRecipient;
    }

    function setFlashLoanFeePercentage(uint newFlashLoanFeePercentage) external onlyOwner {
        require(
            newFlashLoanFeePercentage <= _MAX_PROTOCOL_FLASH_LOAN_FEE_PERCENTAGE,
            "FLASH_LOAN_FEE_PERCENTAGE_TOO_HIGH"
        );
        emit FlashLoanFeePercentageChanged(flashLoanFeePercentage, newFlashLoanFeePercentage);
        flashLoanFeePercentage = newFlashLoanFeePercentage;
    }

    /**
     * @dev Returns the protocol fee amount to charge for a flash loan of `amount`.
     */
    function _calculateFlashLoanFeeAmount(uint amount) internal view returns (uint) {
        return amount * flashLoanFeePercentage / 1e18;
    }

    function _payFeeAmount(address token, uint amount) internal {
        if (amount != 0) {
            address _flashLoanFeeRecipient = flashLoanFeeRecipient;
            TransferHelper.safeTransfer(token, _flashLoanFeeRecipient, amount);
            IFeeRecipient(_flashLoanFeeRecipient).notifyFees(10, token, amount, flashLoanFeePercentage, "");
        }
    }

    /**
     * @dev Performs a 'flash loan', sending tokens to `recipient`, executing the `receiveFlashLoan` hook on it,
     * and then reverting unless the tokens plus a proportional protocol fee have been returned.
     *
     * The `tokens` and `amounts` arrays must have the same length, and each entry in these indicates the loan amount
     * for each token contract. `tokens` must be sorted in ascending order.
     *
     * The 'userData' field is ignored by the Vault, and forwarded as-is to `recipient` as part of the
     * `receiveFlashLoan` call.
     *
     * Emits `FlashLoan` events.
     */
    function flashLoanMultiple(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint[] memory amounts,
        bytes memory userData
    ) external override nonReentrant whenNotPaused {
        uint tokensLength = tokens.length;
        require(tokensLength == amounts.length, "INPUT_LENGTH_MISMATCH");

        uint[] memory feeAmounts = new uint[](tokensLength);
        uint[] memory preLoanBalances = new uint[](tokensLength);

        // Used to ensure `tokens` is sorted in ascending order, which ensures token uniqueness.
        address previousToken;
        uint i;

        address token;
        uint amount;

        for (; i < tokensLength; ) {
            token = tokens[i];
            amount = amounts[i];

            require(token > previousToken, token == address(0) ? "ZERO_TOKEN" : "UNSORTED_TOKENS");
            previousToken = token;

            preLoanBalances[i] = IERC20(token).balanceOf(address(this));
            feeAmounts[i] = _calculateFlashLoanFeeAmount(amount);

            require(preLoanBalances[i] >= amount, "INSUFFICIENT_FLASH_LOAN_BALANCE");
            TransferHelper.safeTransfer(token, address(recipient), amount);

            unchecked {
                ++i;
            }
        }

        recipient.receiveFlashLoan(tokens, amounts, feeAmounts, userData);

        uint preLoanBalance;
        uint postLoanBalance;
        uint receivedFeeAmount;

        for (i = 0; i < tokensLength; ) {
            token = tokens[i];
            preLoanBalance = preLoanBalances[i];

            // Checking for loan repayment first (without accounting for fees) makes for simpler debugging, and results
            // in more accurate revert reasons if the flash loan protocol fee percentage is zero.
            postLoanBalance = IERC20(token).balanceOf(address(this));
            require(postLoanBalance >= preLoanBalance, "INVALID_POST_LOAN_BALANCE");

            // No need for checked arithmetic since we know the loan was fully repaid.
            receivedFeeAmount = postLoanBalance - preLoanBalance;
            require(receivedFeeAmount >= feeAmounts[i], "INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT");

            _payFeeAmount(token, receivedFeeAmount);
            emit FlashLoan(address(recipient), token, amounts[i], receivedFeeAmount);

            unchecked {
                ++i;
            }
        }
    }

    // EIP-3156 Implementations

    /**
     * @dev The amount of currency available to be lent.
     * @param token The loan currency.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address /*token*/, uint256 amount) external view override returns (uint256) {
        return _calculateFlashLoanFeeAmount(amount);
    }

    /**
     * @dev Initiate a flash loan.
     * @param receiver The receiver of the tokens in the loan, and the receiver of the callback.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param userData Arbitrary data structure, intended to contain user-defined parameters.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint amount,
        bytes memory userData
    ) external override nonReentrant whenNotPaused returns (bool) {
        uint preLoanBalance = IERC20(token).balanceOf(address(this));
        uint feeAmount = _calculateFlashLoanFeeAmount(amount);

        require(preLoanBalance >= amount, "INSUFFICIENT_FLASH_LOAN_BALANCE");
        TransferHelper.safeTransfer(token, address(receiver), amount);

        require(
            receiver.onFlashLoan(msg.sender, token, amount, feeAmount, userData) == ERC3156_CALLBACK_SUCCESS,
            "IERC3156_CALLBACK_FAILED"
        );

        // Checking for loan repayment first (without accounting for fees) makes for simpler debugging, and results
        // in more accurate revert reasons if the flash loan protocol fee percentage is zero.
        uint postLoanBalance = IERC20(token).balanceOf(address(this));
        require(postLoanBalance >= preLoanBalance, "INVALID_POST_LOAN_BALANCE");

        // No need for checked arithmetic since we know the loan was fully repaid.
        uint receivedFeeAmount = postLoanBalance - preLoanBalance;
        require(receivedFeeAmount >= feeAmount, "INSUFFICIENT_FLASH_LOAN_FEE_AMOUNT");

        _payFeeAmount(token, receivedFeeAmount);

        emit FlashLoan(address(receiver), token, amount, receivedFeeAmount);
        return true;
    }
}
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/pool/IPool.sol";
import "../interfaces/IFeeManager.sol";

import "../libraries/Ownable.sol";

/// @notice The fee manager manages swap fees for pools and protocol fee.
/// The contract is an independent module and can be replaced in the future.
///
contract SyncSwapFeeManager is IFeeManager, Ownable {
    uint24 private constant MAX_PROTOCOL_FEE = 1e5; /// @dev 100%.
    uint24 private constant MAX_SWAP_FEE = 10000; /// @dev 10%.
    uint24 private constant ZERO_CUSTOM_SWAP_FEE = type(uint24).max;

    /// @dev The default swap fee by pool type.
    mapping(uint16 => uint24) public override defaultSwapFee; /// @dev `300` for 0.3%.

    /// @dev The custom swap fee by pool address, use `ZERO_CUSTOM_SWAP_FEE` for zero fee.
    mapping(address => uint24) public override customSwapFee;

    /// @dev The recipient of protocol fees.
    address public override feeRecipient;

    /// @dev The protocol fee of swap fee by pool type.
    mapping(uint16 => uint24) public override protocolFee; /// @dev `30000` for 30%.

    // Events
    event SetDefaultSwapFee(uint16 indexed poolType, uint24 defaultSwapFee);
    event SetCustomSwapFee(address indexed pool, uint24 customSwapFee);
    event SetProtocolFee(uint16 indexed poolType, uint24 protocolFee);
    event SetFeeRecipient(address indexed previousFeeRecipient, address indexed newFeeRecipient);

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;

        // Prefill fees for known pool types.
        // Classic pools.
        defaultSwapFee[1] = 100; // 0.1%.
        protocolFee[1] = 30000; // 30%.

        // Stable pools.
        defaultSwapFee[2] = 50; // 0.05%.
        protocolFee[2] = 50000; // 50%.
    }

    function getSwapFee(address pool) external view override returns (uint24 swapFee) {
        uint24 _customSwapFee = customSwapFee[pool];

        if (_customSwapFee == 0) {
            swapFee = defaultSwapFee[IPool(pool).poolType()]; // use default instead if not set.
        } else {
            swapFee = (_customSwapFee == ZERO_CUSTOM_SWAP_FEE ? 0 : _customSwapFee);
        }
    }

    function setDefaultSwapFee(uint16 poolType, uint24 _defaultSwapFee) external onlyOwner {
        require(
            _defaultSwapFee <= MAX_SWAP_FEE,
            "INVALID_FEE"
        );
        defaultSwapFee[poolType] = _defaultSwapFee;
        emit SetDefaultSwapFee(poolType, _defaultSwapFee);
    }

    function setCustomSwapFee(address pool, uint24 _customSwapFee) external onlyOwner {
        require(
            _customSwapFee == ZERO_CUSTOM_SWAP_FEE ||
            _customSwapFee <= MAX_SWAP_FEE,
            "INVALID_FEE"
        );
        customSwapFee[pool] = _customSwapFee;
        emit SetCustomSwapFee(pool, _customSwapFee);
    }

    function setProtocolFee(uint16 poolType, uint24 _protocolFee) external onlyOwner {
        require(
            _protocolFee <= MAX_PROTOCOL_FEE,
            "INVALID_FEE"
        );
        protocolFee[poolType] = _protocolFee;
        emit SetProtocolFee(poolType, _protocolFee);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        // Emit here to avoid caching the previous recipient.
        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }
}
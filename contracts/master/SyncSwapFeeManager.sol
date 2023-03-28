// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/pool/IPool.sol";
import "../interfaces/master/IFeeManager.sol";

import "../libraries/Ownable.sol";

/// @notice The fee manager manages swap fees for pools and protocol fee.
/// The contract is an independent module and can be replaced in the future.
///
contract SyncSwapFeeManager is IFeeManager, Ownable {
    uint24 private constant MAX_PROTOCOL_FEE = 1e5; /// @dev 100%.
    uint24 private constant MAX_SWAP_FEE = 10000; /// @dev 10%.
    uint24 private constant ZERO_CUSTOM_FEE = type(uint24).max;

    /// @dev The default swap fee by pool type.
    mapping(uint16 => uint24) public defaultSwapFee; /// @dev `300` for 0.3%.

    /// @dev The custom swap fee by pool address, use `ZERO_CUSTOM_FEE` for zero fee.
    //mapping(address => uint24) public poolSwapFee;

    /// @dev The custom swap fee by tokens, use `ZERO_CUSTOM_FEE` for zero fee.
    mapping(address => mapping(address => uint24)) public tokenSwapFee;

    /// @dev The protocol fee of swap fee by pool type.
    mapping(uint16 => uint24) public defaultProtocolFee; /// @dev `30000` for 30%.

    /// @dev The custom protocol fee by pool address, use `ZERO_CUSTOM_FEE` for zero fee.
    mapping(address => uint24) public poolProtocolFee;

    /// @dev The recipient of protocol fees.
    address public feeRecipient;

    // Events
    event SetDefaultSwapFee(uint16 indexed poolType, uint24 fee);
    event SetTokenSwapFee(address indexed tokenIn, address indexed tokenOut, uint24 fee);
    event SetDefaultProtocolFee(uint16 indexed poolType, uint24 fee);
    event SetPoolProtocolFee(address indexed pool, uint24 fee);
    event SetFeeRecipient(address indexed previousFeeRecipient, address indexed newFeeRecipient);

    constructor(address _feeRecipient) {
        feeRecipient = _feeRecipient;

        // Prefill fees for known pool types.
        // 1 Classic Pools
        defaultSwapFee[1] = 200; // 0.2%.
        defaultProtocolFee[1] = 50000; // 50%.

        // 2 Stable Pools
        defaultSwapFee[2] = 40; // 0.04%.
        defaultProtocolFee[2] = 50000; // 50%.
    }

    // Getters

    function getSwapFee(
        address pool,
        address /*sender*/,
        address tokenIn,
        address tokenOut,
        bytes calldata /*data*/
    ) external view override returns (uint24 fee) {
        fee = tokenSwapFee[tokenIn][tokenOut];

        if (fee == 0) {
            // not set, use default fee of the pool type.
            fee = defaultSwapFee[IPool(pool).poolType()];
        } else {
            // has a pool swap fee.
            fee = (fee == ZERO_CUSTOM_FEE ? 0 : fee);
        }
    }

    function getProtocolFee(address pool) external view override returns (uint24 fee) {
        fee = poolProtocolFee[pool];

        if (fee == 0) {
            // not set, use default fee of the pool type.
            fee = defaultProtocolFee[IPool(pool).poolType()];
        } else {
            // has a pool protocol fee.
            fee = (fee == ZERO_CUSTOM_FEE ? 0 : fee);
        }
    }

    function getFeeRecipient() external view override returns (address) {
        return feeRecipient;
    }

    // Setters

    function setDefaultSwapFee(uint16 poolType, uint24 fee) external onlyOwner {
        require(
            fee <= MAX_SWAP_FEE,
            "Invalid fee"
        );
        defaultSwapFee[poolType] = fee;
        emit SetDefaultSwapFee(poolType, fee);
    }

    function setTokenSwapFee(address tokenIn, address tokenOut, uint24 fee) external onlyOwner {
        require(
            fee == ZERO_CUSTOM_FEE ||
            fee <= MAX_SWAP_FEE,
            "Invalid fee"
        );
        tokenSwapFee[tokenIn][tokenOut] = fee;
        emit SetTokenSwapFee(tokenIn, tokenOut, fee);
    }

    function setDefaultProtocolFee(uint16 poolType, uint24 fee) external onlyOwner {
        require(
            fee <= MAX_PROTOCOL_FEE,
            "Invalid fee"
        );
        defaultProtocolFee[poolType] = fee;
        emit SetDefaultProtocolFee(poolType, fee);
    }

    function setPoolProtocolFee(address pool, uint24 fee) external onlyOwner {
        require(
            fee == ZERO_CUSTOM_FEE ||
            fee <= MAX_PROTOCOL_FEE,
            "Invalid fee"
        );
        poolProtocolFee[pool] = fee;
        emit SetPoolProtocolFee(pool, fee);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        // Emit here to avoid caching the previous recipient.
        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }
}
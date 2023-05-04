// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @dev The callback interface for SyncSwap base pool operations.
/// Note additional checks will be required for some callbacks, see below for more information.
/// Visit the documentation https://syncswap.gitbook.io/api-documentation/ for more details.
interface ICallback {

    struct BaseMintCallbackParams {
        address sender;
        address to;
        uint reserve0;
        uint reserve1;
        uint balance0;
        uint balance1;
        uint amount0;
        uint amount1;
        uint fee0;
        uint fee1;
        uint newInvariant;
        uint oldInvariant;
        uint totalSupply;
        uint liquidity;
        uint24 swapFee;
        bytes callbackData;
    }
    function syncSwapBaseMintCallback(BaseMintCallbackParams calldata params) external;

    struct BaseBurnCallbackParams {
        address sender;
        address to;
        uint balance0;
        uint balance1;
        uint liquidity;
        uint totalSupply;
        uint amount0;
        uint amount1;
        uint8 withdrawMode;
        bytes callbackData;
    }
    function syncSwapBaseBurnCallback(BaseBurnCallbackParams calldata params) external;

    struct BaseBurnSingleCallbackParams {
        address sender;
        address to;
        address tokenIn;
        address tokenOut;
        uint balance0;
        uint balance1;
        uint liquidity;
        uint totalSupply;
        uint amount0;
        uint amount1;
        uint amountOut;
        uint amountSwapped;
        uint feeIn;
        uint24 swapFee;
        uint8 withdrawMode;
        bytes callbackData;
    }
    /// @dev Note the `tokenOut` parameter can be decided by the caller, and the correctness is not guaranteed.
    /// Additional checks MUST be performed in callback to ensure the `tokenOut` is one of the pools tokens if the sender
    /// is not a trusted source to avoid potential issues.
    function syncSwapBaseBurnSingleCallback(BaseBurnSingleCallbackParams calldata params) external;

    struct BaseSwapCallbackParams {
        address sender;
        address to;
        address tokenIn;
        address tokenOut;
        uint reserve0;
        uint reserve1;
        uint balance0;
        uint balance1;
        uint amountIn;
        uint amountOut;
        uint feeIn;
        uint24 swapFee;
        uint8 withdrawMode;
        bytes callbackData;
    }
    /// @dev Note the `tokenIn` parameter can be decided by the caller, and the correctness is not guaranteed.
    /// Additional checks MUST be performed in callback to ensure the `tokenIn` is one of the pools tokens if the sender
    /// is not a trusted source to avoid potential issues.
    function syncSwapBaseSwapCallback(BaseSwapCallbackParams calldata params) external;
}
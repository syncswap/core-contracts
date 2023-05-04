// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../libraries/Math.sol";
import "../../libraries/ERC20Permit2.sol";
import "../../libraries/MetadataHelper.sol";
import "../../libraries/ReentrancyGuard.sol";

import "../../interfaces/ICallback.sol";
import "../../interfaces/vault/IVault.sol";
import "../../interfaces/pool/IClassicPool.sol";
import "../../interfaces/master/IPoolMaster.sol";
import "../../interfaces/master/IFeeRecipient.sol";
import "../../interfaces/factory/IPoolFactory.sol";

error Overflow();
error InsufficientLiquidityMinted();

contract SyncSwapClassicPool is IClassicPool, ERC20Permit2, ReentrancyGuard {
    using Math for uint;

    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.

    /// @dev Pool type `1` for classic pools.
    uint16 public constant override poolType = 1;

    address public immutable override master;
    address public immutable override vault;

    address public immutable override token0;
    address public immutable override token1;

    /// @dev Pool reserve of each pool token as of immediately after the most recent balance event.
    /// The value is used to measure growth in invariant on mints and input tokens on swaps.
    uint public override reserve0;
    uint public override reserve1;

    /// @dev Invariant of the pool as of immediately after the most recent liquidity event.
    /// The value is used to measure growth in invariant when protocol fee is enabled,
    /// and will be reset to zero if protocol fee is disabled.
    uint public override invariantLast;

    /// @dev Factory must ensures that the parameters are valid.
    constructor() {
        (bytes memory _deployData) = IPoolFactory(msg.sender).getDeployData();
        (address _token0, address _token1) = abi.decode(_deployData, (address, address));
        address _master = IPoolFactory(msg.sender).master();

        master = _master;
        vault = IPoolMaster(_master).vault();
        (token0, token1) = (_token0, _token1);

        // try to set symbols for the LP token
        (bool _success0, string memory _symbol0) = MetadataHelper.getSymbol(_token0);
        (bool _success1, string memory _symbol1) = MetadataHelper.getSymbol(_token1);
        if (_success0 && _success1) {
            _initialize(
                string(abi.encodePacked("SyncSwap ", _symbol0, "/", _symbol1, " Classic LP")),
                string(abi.encodePacked(_symbol0, "/", _symbol1, " cSLP"))
            );
        } else {
            _initialize(
                "SyncSwap Classic LP",
                "cSLP"
            );
        }
    }

    function getAssets() external view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /// @dev Returns the verified sender address otherwise `address(0)`.
    function _getVerifiedSender(address _sender) private view returns (address) {
        if (_sender != address(0)) {
            if (_sender != msg.sender) {
                if (!IPoolMaster(master).isForwarder(msg.sender)) {
                    // The sender from non-forwarder is invalid.
                    return address(0);
                }
            }
        }
        return _sender;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(
        bytes calldata _data,
        address _sender,
        address _callback,
        bytes calldata _callbackData
    ) external override nonReentrant returns (uint) {
        ICallback.BaseMintCallbackParams memory params;

        params.to = abi.decode(_data, (address));
        (params.reserve0, params.reserve1) = (reserve0, reserve1);
        (params.balance0, params.balance1) = _balances();

        params.newInvariant = _computeInvariant(params.balance0, params.balance1);
        params.amount0 = params.balance0 - params.reserve0;
        params.amount1 = params.balance1 - params.reserve1;
        //require(_amount0 != 0 && _amount1 != 0);

        // Gets swap fee for the sender.
        _sender = _getVerifiedSender(_sender);
        uint _amount1Optimal = params.reserve0 == 0 ? 0 : (params.amount0 * params.reserve1) / params.reserve0;
        bool _swap0For1 = params.amount1 < _amount1Optimal;
        if (_swap0For1) {
            params.swapFee = _getSwapFee(_sender, token0, token1);
        } else {
            params.swapFee = _getSwapFee(_sender, token1, token0);
        }

        // Adds mint fee to reserves (applies to invariant increase) if unbalanced.
        (params.fee0, params.fee1) = _unbalancedMintFee(params.swapFee, params.amount0, params.amount1, _amount1Optimal, params.reserve0, params.reserve1);
        params.reserve0 += params.fee0;
        params.reserve1 += params.fee1;

        // Calculates old invariant (where unbalanced fee added to) and, mint protocol fee if any.
        params.oldInvariant = _computeInvariant(params.reserve0, params.reserve1);
        bool _feeOn;
        (_feeOn, params.totalSupply) = _mintProtocolFee(0, 0, params.oldInvariant);

        if (params.totalSupply == 0) {
            params.liquidity = params.newInvariant - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock on first mint.
        } else {
            // Calculates liquidity proportional to invariant growth.
            params.liquidity = ((params.newInvariant - params.oldInvariant) * params.totalSupply) / params.oldInvariant;
        }

        // Mints liquidity for recipient.
        if (params.liquidity == 0) {
            revert InsufficientLiquidityMinted();
        }
        _mint(params.to, params.liquidity);

        // Calls callback with data.
        if (_callback != address(0)) {
            // Fills additional values for callback params.
            params.sender = _sender;
            params.callbackData = _callbackData;

            ICallback(_callback).syncSwapBaseMintCallback(params);
        }

        // Updates reserves and last invariant with new balances.
        _updateReserves(params.balance0, params.balance1);
        if (_feeOn) {
            invariantLast = params.newInvariant;
        }

        emit Mint(msg.sender, params.amount0, params.amount1, params.liquidity, params.to);

        return params.liquidity;
    }

    /// @dev Burns LP tokens sent to this contract.
    /// The router should ensure that sufficient pool tokens are received.
    function burn(
        bytes calldata _data,
        address _sender,
        address _callback,
        bytes calldata _callbackData
    ) external override nonReentrant returns (TokenAmount[] memory _amounts) {
        ICallback.BaseBurnCallbackParams memory params;

        (params.to, params.withdrawMode) = abi.decode(_data, (address, uint8));
        (params.balance0, params.balance1) = _balances();
        params.liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        // Note `_mintProtocolFee` here will checks overflow.
        bool _feeOn;
        (_feeOn, params.totalSupply) = _mintProtocolFee(params.balance0, params.balance1, 0);

        // Calculates amounts of pool tokens proportional to balances.
        params.amount0 = params.liquidity * params.balance0 / params.totalSupply;
        params.amount1 = params.liquidity * params.balance1 / params.totalSupply;
        //require(_amount0 != 0 || _amount1 != 0);

        // Burns liquidity and transfers pool tokens.
        _burn(address(this), params.liquidity);
        _transferTokens(token0, params.to, params.amount0, params.withdrawMode);
        _transferTokens(token1, params.to, params.amount1, params.withdrawMode);

        // Updates balances.
        /// @dev Cannot underflow because amounts are lesser figures derived from balances.
        unchecked {
            params.balance0 -= params.amount0;
            params.balance1 -= params.amount1;
        }

        // Calls callback with data.
        // Note reserves are not updated at this point to allow read the old values.
        if (_callback != address(0)) {
            // Fills additional values for callback params.
            params.sender = _getVerifiedSender(_sender);
            params.callbackData = _callbackData;

            ICallback(_callback).syncSwapBaseBurnCallback(params);
        }

        // Updates reserves and last invariant with up-to-date balances (after transfers).
        _updateReserves(params.balance0, params.balance1);
        if (_feeOn) {
            invariantLast = _computeInvariant(params.balance0, params.balance1);
        }

        _amounts = new TokenAmount[](2);
        _amounts[0] = TokenAmount(token0, params.amount0);
        _amounts[1] = TokenAmount(token1, params.amount1);

        emit Burn(msg.sender, params.amount0, params.amount1, params.liquidity, params.to);
    }

    /// @dev Burns LP tokens sent to this contract and swaps one of the output tokens for another
    /// - i.e., the user gets a single token out by burning LP tokens.
    /// The router should ensure that sufficient pool tokens are received.
    function burnSingle(
        bytes calldata _data,
        address _sender,
        address _callback,
        bytes calldata _callbackData
    ) external override nonReentrant returns (TokenAmount memory _tokenAmount) {
        ICallback.BaseBurnSingleCallbackParams memory params;

        (params.tokenOut, params.to, params.withdrawMode) = abi.decode(_data, (address, address, uint8));
        (params.balance0, params.balance1) = _balances();
        params.liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        // Note `_mintProtocolFee` here will checks overflow.
        bool _feeOn;
        (_feeOn, params.totalSupply) = _mintProtocolFee(params.balance0, params.balance1, 0);

        // Calculates amounts of pool tokens proportional to balances.
        params.amount0 = params.liquidity * params.balance0 / params.totalSupply;
        params.amount1 = params.liquidity * params.balance1 / params.totalSupply;

        // Burns liquidity.
        _burn(address(this), params.liquidity);

        // Gets swap fee for the sender.
        _sender = _getVerifiedSender(_sender);

        // Swaps one token for another, transfers desired tokens, and update context values.
        /// @dev Calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped from one token for another.
        if (params.tokenOut == token1) {
            // Swaps `token0` for `token1`.
            params.swapFee = _getSwapFee(_sender, token0, token1);

            params.tokenIn = token0;
            (params.amountSwapped, params.feeIn) = _getAmountOut(
                params.swapFee, params.amount0, params.balance0 - params.amount0, params.balance1 - params.amount1, true
            );
            params.amount1 += params.amountSwapped;

            _transferTokens(token1, params.to, params.amount1, params.withdrawMode);
            params.amountOut = params.amount1;
            params.amount0 = 0;
            params.balance1 -= params.amount1;
        } else {
            // Swaps `token1` for `token0`.
            //require(_tokenOut == token0);
            params.swapFee = _getSwapFee(_sender, token1, token0);

            params.tokenIn = token1;
            (params.amountSwapped, params.feeIn) = _getAmountOut(
                params.swapFee, params.amount1, params.balance0 - params.amount0, params.balance1 - params.amount1, false
            );
            params.amount0 += params.amountSwapped;

            _transferTokens(token0, params.to, params.amount0, params.withdrawMode);
            params.amountOut = params.amount0;
            params.amount1 = 0;
            params.balance0 -= params.amount0;
        }

        // Calls callback with data.
        // Note reserves are not updated at this point to allow read the old values.
        if (_callback != address(0)) {
            // Fills additional values for callback params.
            params.sender = _sender;
            params.callbackData = _callbackData;

            /// @dev Note the `tokenOut` parameter can be decided by the caller, and the correctness is not guaranteed.
            /// Additional checks MUST be performed in callback to ensure the `tokenOut` is one of the pools tokens if the sender
            /// is not a trusted source to avoid potential issues.
            ICallback(_callback).syncSwapBaseBurnSingleCallback(params);
        }

        // Update reserves and last invariant with up-to-date balances (updated above).
        _updateReserves(params.balance0, params.balance1);
        if (_feeOn) {
            invariantLast = _computeInvariant(params.balance0, params.balance1);
        }

        _tokenAmount = TokenAmount(params.tokenOut, params.amountOut);

        emit Burn(msg.sender, params.amount0, params.amount1, params.liquidity, params.to);
    }

    /// @dev Swaps one token for another - should be called via the router after transferring input tokens.
    /// The router should ensure that sufficient output tokens are received.
    function swap(
        bytes calldata _data,
        address _sender,
        address _callback,
        bytes calldata _callbackData
    ) external override nonReentrant returns (TokenAmount memory _tokenAmount) {
        ICallback.BaseSwapCallbackParams memory params;

        (params.tokenIn, params.to, params.withdrawMode) = abi.decode(_data, (address, address, uint8));
        (params.reserve0, params.reserve1) = (reserve0, reserve1);
        (params.balance0, params.balance1) = _balances();

        // Gets swap fee for the sender.
        _sender = _getVerifiedSender(_sender);

        // Calculates output amount, update context values and emit event.
        if (params.tokenIn == token0) {
            params.swapFee = _getSwapFee(_sender, token0, token1);

            params.tokenOut = token1;
            params.amountIn = params.balance0 - params.reserve0;

            (params.amountOut, params.feeIn) = _getAmountOut(params.swapFee, params.amountIn, params.reserve0, params.reserve1, true);
            params.balance1 -= params.amountOut;

            emit Swap(msg.sender, params.amountIn, 0, 0, params.amountOut, params.to);
        } else {
            //require(params.tokenIn == token1);
            params.swapFee = _getSwapFee(_sender, token1, token0);

            params.tokenOut = token0;
            params.amountIn = params.balance1 - params.reserve1;

            (params.amountOut, params.feeIn) = _getAmountOut(params.swapFee, params.amountIn, params.reserve0, params.reserve1, false);
            params.balance0 -= params.amountOut;

            emit Swap(msg.sender, 0, params.amountIn, params.amountOut, 0, params.to);
        }

        // Checks overflow.
        if (params.balance0 > type(uint128).max) {
            revert Overflow();
        }
        if (params.balance1 > type(uint128).max) {
            revert Overflow();
        }

        // Transfers output tokens.
        _transferTokens(params.tokenOut, params.to, params.amountOut, params.withdrawMode);

        // Calls callback with data.
        if (_callback != address(0)) {
            // Fills additional values for callback params.
            params.sender = _sender;
            params.callbackData = _callbackData;

            /// @dev Note the `tokenIn` parameter can be decided by the caller, and the correctness is not guaranteed.
            /// Additional checks MUST be performed in callback to ensure the `tokenIn` is one of the pools tokens if the sender
            /// is not a trusted source to avoid potential issues.
            ICallback(_callback).syncSwapBaseSwapCallback(params);
        }

        // Updates reserves with up-to-date balances (updated above).
        _updateReserves(params.balance0, params.balance1);

        _tokenAmount.token = params.tokenOut;
        _tokenAmount.amount = params.amountOut;
    }

    function _getSwapFee(address _sender, address _tokenIn, address _tokenOut) private view returns (uint24 _swapFee) {
        _swapFee = getSwapFee(_sender, _tokenIn, _tokenOut, "");
    }

    /// @dev This function doesn't check the forwarder.
    function getSwapFee(address _sender, address _tokenIn, address _tokenOut, bytes memory data) public view override returns (uint24 _swapFee) {
        _swapFee = IPoolMaster(master).getSwapFee(address(this), _sender, _tokenIn, _tokenOut, data);
    }

    function getProtocolFee() public view override returns (uint24 _protocolFee) {
        _protocolFee = IPoolMaster(master).getProtocolFee(address(this));
    }

    function _updateReserves(uint _balance0, uint _balance1) private {
        (reserve0, reserve1) = (_balance0, _balance1);
        emit Sync(_balance0, _balance1);
    }

    function _transferTokens(address token, address to, uint amount, uint8 withdrawMode) private {
        if (withdrawMode == 0) {
            IVault(vault).transfer(token, to, amount);
        } else {
            IVault(vault).withdrawAlternative(token, to, amount, withdrawMode);
        }
    }

    function _balances() private view returns (uint balance0, uint balance1) {
        balance0 = IVault(vault).balanceOf(token0, address(this));
        balance1 = IVault(vault).balanceOf(token1, address(this));
    }

    /// @dev This fee is charged to cover for the swap fee when users adding unbalanced liquidity.
    function _unbalancedMintFee(
        uint _swapFee,
        uint _amount0,
        uint _amount1,
        uint _amount1Optimal,
        uint _reserve0,
        uint _reserve1
    ) private pure returns (uint _token0Fee, uint _token1Fee) {
        if (_reserve0 == 0) {
            return (0, 0);
        }
        if (_amount1 >= _amount1Optimal) {
            _token1Fee = (_swapFee * (_amount1 - _amount1Optimal)) / (2 * MAX_FEE);
        } else {
            uint _amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            _token0Fee = (_swapFee * (_amount0 - _amount0Optimal)) / (2 * MAX_FEE);
        }
    }

    function _mintProtocolFee(uint _reserve0, uint _reserve1, uint _invariant) private returns (bool _feeOn, uint _totalSupply) {
        _totalSupply = totalSupply;

        address _feeRecipient = IPoolMaster(master).getFeeRecipient();
        _feeOn = (_feeRecipient != address(0));

        uint _invariantLast = invariantLast;
        if (_invariantLast != 0) {
            if (_feeOn) {
                if (_invariant == 0) {
                    _invariant = _computeInvariant(_reserve0, _reserve1);
                }

                if (_invariant > _invariantLast) {
                    /// @dev Mints `protocolFee` % of growth in liquidity (invariant).
                    uint _protocolFee = getProtocolFee();
                    uint _numerator = _totalSupply * (_invariant - _invariantLast) * _protocolFee;
                    uint _denominator = (MAX_FEE - _protocolFee) * _invariant + _protocolFee * _invariantLast;
                    uint _liquidity = _numerator / _denominator;

                    if (_liquidity != 0) {
                        _mint(_feeRecipient, _liquidity);

                        // Notifies the fee recipient.
                        IFeeRecipient(_feeRecipient).notifyFees(1, address(this), _liquidity, _protocolFee, "");

                        _totalSupply += _liquidity; // update cached value.
                    }
                }
            } else {
                /// @dev Resets last invariant to clear measured growth if protocol fee is not enabled.
                invariantLast = 0;
            }
        }
    }

    function getReserves() external view override returns (uint _reserve0, uint _reserve1) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
    }

    function getAmountOut(address _tokenIn, uint _amountIn, address _sender) external view override returns (uint _amountOut) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        bool _swap0For1 = _tokenIn == token0;
        address _tokenOut = _swap0For1 ? token1 : token0;
        (_amountOut,) = _getAmountOut(_getSwapFee(_sender, _tokenIn, _tokenOut), _amountIn, _reserve0, _reserve1, _swap0For1);
    }

    function getAmountIn(address _tokenOut, uint _amountOut, address _sender) external view override returns (uint _amountIn) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        bool _swap1For0 = _tokenOut == token0;
        address _tokenIn = _swap1For0 ? token1 : token0;
        _amountIn = _getAmountIn(_getSwapFee(_sender, _tokenIn, _tokenOut), _amountOut, _reserve0, _reserve1, _swap1For0);
    }

    function _getAmountOut(
        uint _swapFee,
        uint _amountIn,
        uint _reserve0,
        uint _reserve1,
        bool _token0In
    ) private pure returns (uint _dy, uint _feeIn) {
        if (_amountIn == 0) {
            _dy = 0;
        } else {
            uint _amountInWithFee = _amountIn * (MAX_FEE - _swapFee);
            _feeIn = _amountIn * _swapFee / MAX_FEE;

            if (_token0In) {
                _dy = (_amountInWithFee * _reserve1) / (_reserve0 * MAX_FEE + _amountInWithFee);
            } else {
                _dy = (_amountInWithFee * _reserve0) / (_reserve1 * MAX_FEE + _amountInWithFee);
            }
        }
    }

    function _getAmountIn(
        uint _swapFee,
        uint _amountOut,
        uint _reserve0,
        uint _reserve1,
        bool _token0Out
    ) private pure returns (uint _dx) {
        if (_amountOut == 0) {
            _dx = 0;
        } else {
            if (_token0Out) {
                _dx = (_reserve1 * _amountOut * MAX_FEE) / ((_reserve0 - _amountOut) * (MAX_FEE - _swapFee)) + 1;
            } else {
                _dx = (_reserve0 * _amountOut * MAX_FEE) / ((_reserve1 - _amountOut) * (MAX_FEE - _swapFee)) + 1;
            }
        }
    }

    function _computeInvariant(uint _reserve0, uint _reserve1) private pure returns (uint _invariant) {
        if (_reserve0 > type(uint128).max) {
            revert Overflow();
        }
        if (_reserve1 > type(uint128).max) {
            revert Overflow();
        }
        _invariant = (_reserve0 * _reserve1).sqrt();
    }
}
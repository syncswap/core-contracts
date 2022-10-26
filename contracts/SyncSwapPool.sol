// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./libraries/Lock.sol";
import "./libraries/Math.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IBasePool.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ISyncSwapFactory.sol";
import "./interfaces/ISyncSwapCallback.sol";
import "./SyncSwapERC20.sol";

error InsufficientInputAmount();
error InsufficientLiquidityMinted();

contract SyncSwapPool is IBasePool, SyncSwapERC20, Lock {
    using Math for uint;

    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant MAX_LOOP_LIMIT = 256;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.

    address public immutable override factory;
    address public immutable override token0;
    address public immutable override token1;
    address public immutable vault;

    /// @dev Amplification coefficient chosen from fluctuation of prices around 1 = 1.
    /// The value also determines whether the pool is using the StableSwap invariant (when A != 0).
    uint public override A;
    uint private N_A; /// @dev 2 * A.

    /// @dev Multipliers for each pooled token's precision to get to the pool precision decimals
    /// which is agnostic to the pool, but usually is 18.
    /// For example, TBTC has 18 decimals, so the multiplier should be 10 ** (18 - 18) = 1.
    /// WBTC has 8, so the multiplier should be 10 ** (18 - 8) => 10 ** 10.
    /// The value is only for stable pools, and has no effects on non-stable pools.
    uint public immutable override token0PrecisionMultiplier;
    uint public immutable override token1PrecisionMultiplier;

    /// @dev Pool reserve of each pool token as of immediately after the most recent balance event.
    /// The value is used to measure growth in invariant on mints and input tokens on swaps.
    uint public override reserve0;
    uint public override reserve1;
    /// @dev Invariant of the pool as of immediately after the most recent liquidity event.
    /// The value is used to measure growth in invariant when protocol fee is enabled,
    /// and will be reset to zero if protocol fee is disabled.
    uint public override invariantLast;

    /// @dev Factory must ensures that the parameters are valid.
    constructor(address _vault, address _token0, address _token1, uint _a, uint _token0PrecisionMultiplier, uint _token1PrecisionMultiplier) {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        vault = _vault;
        A = _a;
        N_A = 2 * _a;
        token0PrecisionMultiplier = _token0PrecisionMultiplier;
        token1PrecisionMultiplier = _token1PrecisionMultiplier;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(bytes calldata _data) external override lock returns (uint _liquidity) {
        address _to = abi.decode(_data, (address));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        uint _newInvariant = _computeInvariant(_balance0, _balance1);
        uint _amount0 = _balance0 - _reserve0;
        uint _amount1 = _balance1 - _reserve1;
        //require(_amount0 != 0 && _amount1 != 0); // unchecked to save gas as not necessary

        {
        // Adds mint fee to reserves (applies to invariant increase) if unbalanced.
        (uint _fee0, uint _fee1) = _unbalancedMintFee(_amount0, _amount1, _reserve0, _reserve1);
        _reserve0 += _fee0;
        _reserve1 += _fee1;
        }

        {
        // Calculates old invariant (where unbalanced fee added to) and, mint protocol fee if any.
        (bool _feeOn, uint _totalSupply, uint _oldInvariant) = _mintProtocolFee(_reserve0, _reserve1);

        if (_totalSupply == 0) {
            _liquidity = _newInvariant - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock on first mint.
        } else {
            // Calculates liquidity proportional to invariant growth.
            _liquidity = ((_newInvariant - _oldInvariant) * _totalSupply) / _oldInvariant;
        }

        // Mints liquidity for recipient.
        if (_liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(_to, _liquidity);

        // Updates reserves and last invariant with new balances.
        _updateReserves(_balance0, _balance1);
        if (_feeOn) {
            invariantLast = _newInvariant;
        }
        }

        emit Mint(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    /// @dev Burns LP tokens sent to this contract.
    /// The router should ensure that sufficient pool tokens are received.
    function burn(bytes calldata _data) external override lock returns (TokenAmount[] memory _amounts) {
        (address _to, bool _withdraw) = abi.decode(_data, (address, bool));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        // TODO can they mess up the pool if transferred some unbalanced tokens on purpose?
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;
        //require(_amount0 != 0 || _amount1 != 0); // unchecked to save gas, should be done through router.

        // Burns liquidity and transfers pool tokens.
        _burn(address(this), _liquidity);
        _transferTokens(token0, _to, _amount0, _withdraw);
        _transferTokens(token1, _to, _amount1, _withdraw);

        // Update reserves and last invariant with up-to-date balances (after transfers).
        /// @dev Using counterfactuals balances here to save gas.
        /// Cannot underflow because amounts will never be smaller than balances.
        unchecked {
            _balance0 -= _amount0;
            _balance1 -= _amount1;
        }
        _updateReserves(_balance0, _balance1);
        if (_feeOn) {
            invariantLast = _computeInvariant(_balance0, _balance1);
        }

        _amounts = new TokenAmount[](2);
        _amounts[0] = TokenAmount(token0, _amount0);
        _amounts[1] = TokenAmount(token1, _amount1);

        emit Burn(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    /// @dev Burns LP tokens sent to this contract and swaps one of the output tokens for another
    /// - i.e., the user gets a single token out by burning LP tokens.
    /// The router should ensure that sufficient pool tokens are received.
    function burnSingle(bytes calldata _data) external override lock returns (uint _amountOut) {
        (address _tokenOut, address _to, bool _withdraw) = abi.decode(_data, (address, address, bool));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;

        // Burns liquidity and, update last invariant using counterfactuals balances.
        _burn(address(this), _liquidity);

        // Swap one token for another, transfers desired tokens, and update context values.
        /// @dev Calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped from one token for another.
        if (_tokenOut == token1) {
            // Swap `token0` for `token1`.
            _amount1 += _getAmountOut(_amount0, _balance0 - _amount0, _balance1 - _amount1, true);
            _transferTokens(token1, _to, _amount1, _withdraw);
            _amountOut = _amount1;
            _amount0 = 0;
            _balance1 -= _amount1;
            // TODO Check gas if emit burn event here.
        } else {
            // Swap `token1` for `token0`.
            require(_tokenOut == token0); // ensures to prevent from messing up the pool with bad parameters.
            _amount0 += _getAmountOut(_amount1, _balance0 - _amount0, _balance1 - _amount1, false);
            _transferTokens(token0, _to, _amount0, _withdraw);
            _amountOut = _amount0;
            _amount1 = 0;
            _balance0 -= _amount0;
        }

        // Update reserves and last invariant with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);
        if (_feeOn) {
            invariantLast = _computeInvariant(_balance0, _balance1);
        }

        emit Burn(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    /// @dev Swaps one token for another - should be called via the router after transferring input tokens.
    /// The router should ensure that sufficient output tokens are received.
    function swap(bytes calldata _data) external override lock returns (uint _amountOut) {
        (address _tokenIn, address _to, bool _withdraw) = abi.decode(_data, (address, address, bool));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        // Calculates output amount, update context values and emit event.
        uint _amountIn;
        address _tokenOut;
        if (_tokenIn == token0) {
            _tokenOut = token1;
            // Cannot underflow because reserve will never be larger than balance.
            unchecked {
                _amountIn = _balance0 - _reserve0;
            }
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, true);
            _balance1 -= _amountOut;

            emit Swap(msg.sender, _amountIn, 0, 0, _amountOut, _to); // emit here to avoid checking direction 
        } else {
            require(_tokenIn == token1); // ensures to prevent counterfeit event parameters.
            _tokenOut = token0;
            // Cannot underflow because reserve will never be larger than balance.
            unchecked {
                _amountIn = _balance1 - reserve1;
            }
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, false);
            _balance0 -= _amountOut;

            emit Swap(msg.sender, 0, _amountIn, _amountOut, 0, _to); // emit here to avoid checking direction 
        }

        // Transfers output tokens.
        _transferTokens(_tokenOut, _to, _amountOut, _withdraw);

        // Update reserves with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);
    }

    /*
    /// @dev Swaps one token for another with callback.
    /// The router / caller must transfers sufficient input tokens before calling or during the callback.
    function flashSwap(bytes calldata _data) external lock returns (uint _amountIn0, uint _amountIn1) {
        (uint _amountOut0, uint _amountOut1, address _to, bool _withdraw, bytes memory _context) = abi.decode(
            _data,
            (uint, uint, address, bytes)
        );
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);

        // Transfers output tokens optimistically, and calculates input tokens required.
        if (_amountOut0 != 0) {
            _transferTokens(token0, _to, _amountOut0, _withdraw);
            _amountIn1 = _getAmountIn(_amountOut0, _reserve0, _reserve1, true);
        }
        if (_amountOut1 != 0) {
            _transferTokens(token1, _to, _amountOut1, _withdraw);
            _amountIn0 = _getAmountIn(_amountOut1, _reserve0, _reserve1, false);
        }

        // Calls the callback with amounts if has context.
        if (_context.length != 0) {
            ISyncSwapCallback(msg.sender).syncSwapCallback(_amountIn0, _amountIn1, _amountOut0, _amountOut1, _to, _context);
        }

        // Ensures required input tokens are received.
        (uint _balance0, uint _balance1) = _balances();
        {
        uint _actualAmountIn0 = _balance0 > (_reserve0 - _amountOut0) ? _balance0 - (_reserve0 - _amountOut0) : 0;
        uint _actualAmountIn1 = _balance1 > (_reserve1 - _amountOut1) ? _balance1 - (_reserve1 - _amountOut1) : 0;
        /// @dev Excessive inputs are ignored.
        if (_actualAmountIn0 < _amountIn0) revert InsufficientInputAmount();
        if (_actualAmountIn1 < _amountIn1) revert InsufficientInputAmount();
        }

        // Updates reserves with new balances.
        _updateReserves(_balance0, _balance1);

        emit Swap(msg.sender, _amountIn0, _amountIn1, _amountOut0, _amountOut1, _to);
    }
    */

    function _updateReserves(uint _balance0, uint _balance1) private {
        (reserve0, reserve1) = (_balance0, _balance1);
        emit Sync(_balance0, _balance1);
    }

    function _transferTokens(address token, address to, uint amount, bool withdraw) private {
        if (withdraw) {
            IVault(vault).withdraw(token, to, amount);
        } else {
            IVault(vault).transfer(token, to, amount);
        }
    }

    function _balances() private view returns (uint balance0, uint balance1) {
        //_balance0 = IERC20(token0).balanceOf(address(this));
        //_balance1 = IERC20(token1).balanceOf(address(this));
        balance0 = IVault(vault).balanceOf(token0, address(this));
        balance1 = IVault(vault).balanceOf(token1, address(this));
    }

    function _getSwapFee() private view returns (uint24 _swapFee) {
        _swapFee = ISyncSwapFactory(factory).getSwapFee(address(this));
    }

    /// @dev This fee is charged to cover for the swap fee when users add unbalanced liquidity.
    function _unbalancedMintFee(
        uint _amount0,
        uint _amount1,
        uint _reserve0,
        uint _reserve1
    ) private view returns (uint _token0Fee, uint _token1Fee) {
        if (_reserve0 == 0 || _reserve1 == 0) {
            return (0, 0);
        }
        uint _amount1Optimal = (_amount0 * _reserve1) / _reserve0;
        if (_amount1 >= _amount1Optimal) {
            _token1Fee = (_getSwapFee() * (_amount1 - _amount1Optimal)) / (2 * MAX_FEE);
        } else {
            uint _amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            _token0Fee = (_getSwapFee() * (_amount0 - _amount0Optimal)) / (2 * MAX_FEE);
        }
    }

    function _mintProtocolFee(uint _reserve0, uint _reserve1) private returns (bool _feeOn, uint _totalSupply, uint _invariant) {
        _totalSupply = totalSupply;
        _invariant = _computeInvariant(_reserve0, _reserve1);

        address _feeRecipient = ISyncSwapFactory(factory).feeRecipient();
        _feeOn = (_feeRecipient != address(0));

        uint _invariantLast = invariantLast;
        if (_invariantLast != 0) {
            if (_feeOn) {
                if (_invariant > _invariantLast) {
                    /// @dev Mints `protocolFee` % of growth in liquidity (invariant).
                    uint _protocolFee = ISyncSwapFactory(factory).protocolFee();
                    uint _numerator = _totalSupply * (_invariant - _invariantLast) * _protocolFee;
                    uint _denominator = (MAX_FEE - _protocolFee) * _invariant + _protocolFee * _invariantLast;
                    uint _liquidity = _numerator / _denominator;

                    if (_liquidity != 0) {
                        _mint(_feeRecipient, _liquidity);
                        _totalSupply += _liquidity; // update cached value.
                    }
                }
            } else {
                /// @dev Reset last invariant to clear measured growth if protocol fee is not enabled.
                invariantLast = 0;
            }
        }
    }

    function getReserves() external view override returns (uint _reserve0, uint _reserve1) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
    }

    function getAmountOut(address _tokenIn, uint _amountIn) external view override returns (uint _finalAmountOut) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        _finalAmountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, _tokenIn == token0);
    }

    function getAmountIn(address _tokenOut, uint256 _amountOut) external view override returns (uint _finalAmountIn) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        _finalAmountIn = _getAmountIn(_amountOut, _reserve0, _reserve1, _tokenOut == token0);
    }

    function _getAmountOut(
        uint _amountIn,
        uint _reserve0,
        uint _reserve1,
        bool _token0In
    ) private view returns (uint _dy) {
        if (_amountIn == 0) {
            _dy = 0;
        } else {
            if (A != 0) {
                unchecked {
                    uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                    uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                    uint _feeDeductedAmountIn = _amountIn - (_amountIn * _getSwapFee()) / MAX_FEE;
                    uint _d = _computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                    if (_token0In) {
                        uint _x = _adjustedReserve0 + (_feeDeductedAmountIn * token0PrecisionMultiplier);
                        uint _y = _getY(_x, _d);
                        _dy = _adjustedReserve1 - _y - 1;
                        _dy /= token1PrecisionMultiplier;
                    } else {
                        uint _x = _adjustedReserve1 + (_feeDeductedAmountIn * token1PrecisionMultiplier);
                        uint _y = _getY(_x, _d);
                        _dy = _adjustedReserve0 - _y - 1;
                        _dy /= token0PrecisionMultiplier;
                    }
                }
            } else {
                uint _amountInWithFee = _amountIn * (MAX_FEE - _getSwapFee());
                if (_token0In) {
                    _dy = (_amountInWithFee * _reserve1) / (_reserve0 * MAX_FEE + _amountInWithFee);
                } else {
                    _dy = (_amountInWithFee * _reserve0) / (_reserve1 * MAX_FEE + _amountInWithFee);
                }
            }
        }
    }

    function _getAmountIn(
        uint _amountOut,
        uint _reserve0,
        uint _reserve1,
        bool _token0Out
    ) private view returns (uint _dx) {
        if (_amountOut == 0) {
            _dx = 0;
        } else {
            if (A != 0) {
                unchecked {
                    uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                    uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                    uint _d = _computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                    if (_token0Out) {
                        uint _y = _adjustedReserve0 - _amountOut;
                        if (_y <= 1) {
                            return 1;
                        }
                        uint _x = _getY(_y, _d);
                        _dx = MAX_FEE * (_x - _adjustedReserve1) / (MAX_FEE - _getSwapFee()) + 1;
                        _dx /= token1PrecisionMultiplier;
                    } else {
                        uint _y = _adjustedReserve1 - _amountOut;
                        if (_y <= 1) {
                            return 1;
                        }
                        uint _x = _getY(_y, _d);
                        _dx = MAX_FEE * (_x - _adjustedReserve0) / (MAX_FEE - _getSwapFee()) + 1;
                        _dx /= token0PrecisionMultiplier;
                    }
                }
            } else {
                if (_token0Out) {
                    _dx = (_reserve1 * _amountOut * MAX_FEE) / ((_reserve0 - _amountOut) * (MAX_FEE - _getSwapFee())) + 1;
                } else {
                    _dx = (_reserve0 * _amountOut * MAX_FEE) / ((_reserve1 - _amountOut) * (MAX_FEE - _getSwapFee())) + 1;
                }
            }
        }
    }

    /// @notice Calculate the new balances of the tokens given the indexes of the token
    /// that is swapped from (FROM) and the token that is swapped to (TO).
    /// This function is used as a helper function to calculate how much TO token
    /// the user should receive on swap.
    /// @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432.
    /// @param x The new total amount of FROM token.
    /// @return y The amount of TO token that should remain in the pool.
    function _getY(uint x, uint _d) private view returns (uint y) {
        uint c = (_d * _d) / (x * 2);
        c = (c * _d) / (N_A * 2);
        uint b = x + (_d / N_A);
        uint yPrev;
        y = _d;
        /// @dev Iterative approximation.
        for (uint i; i < MAX_LOOP_LIMIT; ) {
            yPrev = y;
            y = (y * y + c) / (y * 2 + b - _d);
            if (y.within1(yPrev)) {
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _computeInvariant(uint _reserve0, uint _reserve1) private view returns (uint _invariant) {
        if (A != 0) {
            /// @dev Get D, the StableSwap invariant, based on a set of balances and a particular A.
            /// See the StableSwap paper for details.
            /// Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319.
            /// Returns the invariant, at the precision of the pool.
            unchecked {
                uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                _invariant = _computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);
            }
        } else {
            _invariant = (_reserve0 * _reserve1).sqrt();
        }
    }

    function _computeDFromAdjustedBalances(uint _xp0, uint _xp1) private view returns (uint _computed) {
        uint _s = _xp0 + _xp1;

        if (_s == 0) {
            _computed = 0;
        } else {
            uint _prevD;
            uint _d = _s;
            for (uint i; i < MAX_LOOP_LIMIT; ) {
                uint _dP = (((_d * _d) / _xp0) * _d) / _xp1 / 4;
                _prevD = _d;
                _d = (((N_A * _s) + 2 * _dP) * _d) / ((N_A - 1) * _d + 3 * _dP);
                if (_d.within1(_prevD)) {
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            _computed = _d;
        }
    }
}
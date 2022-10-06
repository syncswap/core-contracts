// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./libraries/Lock.sol";
import "./libraries/Math.sol";
import "./libraries/TransferHelper.sol";
import "./interfaces/ISyncSwapPool.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISyncSwapFactory.sol";
import "./interfaces/ISyncSwapCallback.sol";
import "./SyncSwapERC20.sol";
import "./SyncSwapLibrary.sol";

contract SyncSwapPool is ISyncSwapPool, SyncSwapERC20, Lock {
    using Math for uint;

    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant MAX_LOOP_LIMIT = 256;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.

    address public immutable override factory;
    address public immutable override token0;
    address public immutable override token1;
    /// @dev Whether the pool is stable, determines the invariant to use (either x*y=k or hybrid).
    bool public immutable override stable;

    /// @dev Amplification coefficient chosen from fluctuation of prices around 1 = 1.
    /// The value is only for stable pools, and has no effects on non-stable pools.
    uint public A;
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
    uint private invariantLast;

    /// @dev Factory must ensures that the parameters are valid.
    constructor(address _token0, address _token1, uint _a, uint _token0PrecisionMultiplier, uint _token1PrecisionMultiplier) payable {
        factory = msg.sender;
        token0 = _token0;
        token1 = _token1;
        if (_a != 0) {
            stable = true;
            A = _a;
            N_A = 2.mulUnsafeFirst(_a);
            token0PrecisionMultiplier = _token0PrecisionMultiplier;
            token1PrecisionMultiplier = _token1PrecisionMultiplier;
        }
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(address _to) external override lock returns (uint _liquidity) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        uint _newInvariant = _computeInvariant(_balance0, _balance1);
        uint _amount0 = _balance0 - _reserve0;
        uint _amount1 = _balance1 - _reserve1;
        //require(_amount0 != 0 && _amount1 != 0); // unchecked to save gas as not necessary

        // Adds mint fee to reserves (applies to invariant increase) if unbalanced.
        (uint _fee0, uint _fee1) = _unbalancedMintFee(_amount0, _amount1, _reserve0, _reserve1);
        _reserve0 += _fee0;
        _reserve1 += _fee1;

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
        require(_liquidity != 0, "M"); // INSUFFICIENT_LIQUIDITY_MINTED
        _mint(_to, _liquidity);

        // Updates reserves and last invariant with new balances.
        _updateReserves(_balance0, _balance1);
        if (_feeOn) {
            invariantLast = _newInvariant;
        }

        emit Mint(msg.sender, _amount0, _amount1, _to, _liquidity);
    }

    /// @dev Burns LP tokens sent to this contract.
    /// The router should ensure that sufficient pool tokens are received.
    function burn(address _to) external override lock returns (uint _amount0, uint _amount1) {
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        // TODO can they mess up the pool if transferred some unbalanced tokens on purpose?
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        _amount0 = _liquidity.mulDiv(_balance0, _totalSupply);
        _amount1 = _liquidity.mulDiv(_balance1, _totalSupply);
        //require(_amount0 != 0 || _amount1 != 0); // unchecked to save gas, should be done through router.

        // Burns liquidity and transfers pool tokens.
        _burn(address(this), _liquidity);
        TransferHelper.safeTransfer(token0, _to, _amount0);
        TransferHelper.safeTransfer(token1, _to, _amount1);

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

        emit Burn(msg.sender, _amount0, _amount1, _to, _liquidity);
    }

    /// @dev Burns LP tokens sent to this contract and swaps one of the output tokens for another
    /// - i.e., the user gets a single token out by burning LP tokens.
    /// The router should ensure that sufficient pool tokens are received.
    function burnSingle(address _tokenOut, address _to) external override lock returns (uint _amountOut) {
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity.mulDiv(_balance0, _totalSupply);
        uint _amount1 = _liquidity.mulDiv(_balance1, _totalSupply);

        // Burns liquidity and, update last invariant using counterfactuals balances.
        _burn(address(this), _liquidity);

        // Swap one token for another, transfers desired tokens, and update context values.
        /// @dev Calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped from one token for another.
        if (_tokenOut == token1) {
            // Swap `token0` for `token1`.
            _amount1 += _getAmountOut(_amount0, _balance0 - _amount0, _balance1 - _amount1, true);
            TransferHelper.safeTransfer(token1, _to, _amount1);
            _amountOut = _amount1;
            _amount0 = 0;
            _balance1 -= _amount1;
            // TODO Check gas if emit burn event here.
        } else {
            // Swap `token1` for `token0`.
            require(_tokenOut == token0); // ensures to prevent from messing up the pool with bad parameters.
            _amount0 += _getAmountOut(_amount1, _balance0 - _amount0, _balance1 - _amount1, false);
            TransferHelper.safeTransfer(token0, _to, _amount0);
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

        emit Burn(msg.sender, _amount0, _amount1, _to, _liquidity);
    }

    /// @dev Swaps one token for another - should be called via the router after transferring input tokens.
    /// The router should ensure that sufficient output tokens are received.
    function swap(address _tokenIn, address _to) external override lock returns (uint _amountOut) {
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
        TransferHelper.safeTransfer(_tokenOut, _to, _amountOut);

        // Update reserves with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);
    }

    /// @dev Swaps one token for another with callback.
    /// The router / caller must transfers sufficient input tokens before calling or during the callback.
    function flashSwap(uint _amountOut0, uint _amountOut1, address _to, bytes calldata _data) external lock returns (uint _amountIn0, uint _amountIn1) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        //(uint _balance0, uint _balance1) = _balances();

        // Transfers output tokens optimistically, and calculates input tokens required.
        if (_amountOut0 != 0) {
            TransferHelper.safeTransfer(token0, _to, _amountOut0);
            _amountIn1 = _getAmountIn(_amountOut0, _reserve0, _reserve1, true);
        }
        if (_amountOut1 != 0) {
            TransferHelper.safeTransfer(token1, _to, _amountOut1);
            _amountIn0 = _getAmountIn(_amountOut1, _reserve0, _reserve1, false);
        }

        // Calls the callback with amounts if has data.
        if (_data.length != 0) {
            ISyncSwapCallback(msg.sender).syncSwapCallback(_amountIn0, _amountIn1, _amountOut0, _amountOut1, _data);
        }

        // Ensures required input tokens are received.
        /// @dev Excessive inputs are ignored.
        (uint _balance0, uint _balance1) = _balances();
        uint _actualAmountIn0 = _balance0 > (_reserve0 - _amountOut0) ? _balance0 - (_reserve0 - _amountOut0) : 0;
        uint _actualAmountIn1 = _balance1 > (_reserve1 - _amountOut1) ? _balance1 - (_reserve1 - _amountOut1) : 0;
        require(_actualAmountIn0 >= _amountIn0 && _actualAmountIn1 >= _amountIn1, "IAI"); // INSUFFICIENT_AMOUNT_IN

        // Updates reserves with new balances.
        _updateReserves(_balance0, _balance1);

        emit Swap(msg.sender, _amountIn0, _amountIn1, _amountOut0, _amountOut1, _to);
    }

    function _updateReserves(uint _balance0, uint _balance1) private {
        (reserve0, reserve1) = (_balance0, _balance1);
        emit Sync(_balance0, _balance1);
    }

    function _balances() private view returns (uint _balance0, uint _balance1) {
        _balance0 = IERC20(token0).balanceOf(address(this));
        _balance1 = IERC20(token1).balanceOf(address(this));
    }

    function _getSwapFee() private view returns (uint16 _swapFee) {
        _swapFee = ISyncSwapFactory(factory).getSwapFee(address(this), msg.sender);
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
        //uint _amount1Optimal = (_amount0 * _reserve1) / _reserve0;
        uint _amount1Optimal = _amount0.mulDiv(_reserve1, _reserve0);
        if (_amount1 >= _amount1Optimal) {
            //_token1Fee = (_getSwapFee() * (_amount1 - _amount1Optimal)) / (2 * MAX_FEE);
            _token1Fee = _getSwapFee().mulDivUnsafeLast(
                (_amount1 - _amount1Optimal),
                (2 * MAX_FEE)
            );
        } else {
            //uint _amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            uint _amount0Optimal = _amount1.mulDiv(_reserve0, _reserve1);
            //_token0Fee = (_getSwapFee() * (_amount0 - _amount0Optimal)) / (2 * MAX_FEE);
            _token1Fee = _getSwapFee().mulDivUnsafeLast(
                (_amount0 - _amount0Optimal),
                (2 * MAX_FEE)
            );
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
                    uint _numerator = (_invariant - _invariantLast).mulUnsafeFirst(_totalSupply).mul(_protocolFee);
                    uint _denominator = _invariant.mulUnsafeFirst(MAX_FEE - _protocolFee) + _invariantLast.mulUnsafeFirst(_protocolFee);
                    uint _liquidity = _numerator.div(_denominator);

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

    function getAmountOut(address _tokenIn, uint _amountIn) external view override returns (uint _finalAmountOut) {
        _finalAmountOut = _getAmountOut(_amountIn, reserve0, reserve1, _tokenIn == token0);
    }

    function getAmountIn(address _tokenOut, uint256 _amountOut) external view override returns (uint _finalAmountIn) {
        _finalAmountIn = _getAmountIn(_amountOut, reserve0, reserve1, _tokenOut == token0);
    }

    function _getAmountOut(
        uint _amountIn,
        uint _reserve0,
        uint _reserve1,
        bool _token0In
    ) private view returns (uint _dy) {
        if (stable) {
            unchecked {
                uint _adjustedReserve0 = token0PrecisionMultiplier.mulUnsafeFirst(_reserve0);
                uint _adjustedReserve1 = token1PrecisionMultiplier.mulUnsafeFirst(_reserve1);
                uint _feeDeductedAmountIn = _amountIn - _amountIn.mulDivUnsafeLast(_getSwapFee(), MAX_FEE);
                uint _d = _computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                if (_token0In) {
                    uint _x = _adjustedReserve0 + (token0PrecisionMultiplier.mulUnsafeFirst(_feeDeductedAmountIn));
                    uint _y = _getY(_x, _d);
                    _dy = _adjustedReserve1 - _y - 1;
                    _dy /= token1PrecisionMultiplier;
                } else {
                    uint _x = _adjustedReserve1 + (token1PrecisionMultiplier.mulUnsafeFirst(_feeDeductedAmountIn));
                    uint _y = _getY(_x, _d);
                    _dy = _adjustedReserve0 - _y - 1;
                    _dy /= token0PrecisionMultiplier;
                }
            }
        } else {
            uint _amountInWithFee = _amountIn.mul(MAX_FEE - _getSwapFee());
            if (_token0In) {
                //_dy = (_amountInWithFee * _reserve1) / (_reserve0 * MAX_FEE + _amountInWithFee);
                _dy = _amountInWithFee.mulDiv(
                    _reserve1,
                    (MAX_FEE.mulUnsafeFirst(_reserve0) + _amountInWithFee)
                );
            } else {
                //_dy = (_amountInWithFee * _reserve0) / (_reserve1 * MAX_FEE + _amountInWithFee);
                _dy = _amountInWithFee.mulDiv(
                    _reserve0,
                    (MAX_FEE.mulUnsafeFirst(_reserve1) + _amountInWithFee)
                );
            }
        }
    }

    function _getAmountIn(
        uint _amountOut,
        uint _reserve0,
        uint _reserve1,
        bool _token0Out
    ) private view returns (uint _dx) {
        if (stable) {
            unchecked {
                uint _adjustedReserve0 = token0PrecisionMultiplier.mulUnsafeFirst(_reserve0);
                uint _adjustedReserve1 = token1PrecisionMultiplier.mulUnsafeFirst(_reserve1);
                uint _d = _computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                if (_token0Out) {
                    uint _y = _adjustedReserve0 - _amountOut;
                    if (_y <= 1) {
                        return 1;
                    }
                    uint _x = _getY(_y, _d);
                    //_dx = MAX_FEE.mulUnsafeFirst(_x - _adjustedReserve1).divUnsafeLast((MAX_FEE - _getSwapFee()) + 1);
                    /// @dev It's safe here because both `MAX_FEE` and `(MAX_FEE - _getSwapFee()) + 1` will never be zero.
                    _dx = MAX_FEE.mulDivUnsafeBoth(
                        _x - _adjustedReserve1,
                        (MAX_FEE - _getSwapFee()) + 1
                    );
                    _dx = _dx.divUnsafeLast(token1PrecisionMultiplier);
                } else {
                    uint _y = _adjustedReserve1 - _amountOut;
                    if (_y <= 1) {
                        return 1;
                    }
                    uint _x = _getY(_y, _d);
                    //_dx = MAX_FEE.mulUnsafeFirst(_x - _adjustedReserve0).divUnsafeLast((MAX_FEE - _getSwapFee()) + 1);
                    /// @dev It's safe here because both `MAX_FEE` and `(MAX_FEE - _getSwapFee()) + 1` will never be zero.
                    _dx = MAX_FEE.mulDivUnsafeBoth(
                        _x - _adjustedReserve0,
                        (MAX_FEE - _getSwapFee()) + 1
                    );
                    _dx = _dx.divUnsafeLast(token0PrecisionMultiplier);
                }
            }
        } else {
            if (_token0Out) {
                //_dx = (_reserve1 * _amountOut * MAX_FEE) / ((_reserve0 - _amountOut) * (MAX_FEE - _getSwapFee())) + 1;
                _dx = MAX_FEE.mulDivUnsafeFirst(
                    _reserve1.mul(_amountOut),
                    ((_reserve0 - _amountOut).mul(MAX_FEE - _getSwapFee()))
                ) + 1;
            } else {
                //_dx = (_reserve0 * _amountOut * MAX_FEE) / ((_reserve1 - _amountOut) * (MAX_FEE - _getSwapFee())) + 1;
                _dx = MAX_FEE.mulDivUnsafeFirst(
                    _reserve0.mul(_amountOut),
                    ((_reserve1 - _amountOut).mul(MAX_FEE - _getSwapFee()))
                ) + 1;
            }
        }
    }

    /// @notice Calculate the new balances of the tokens given the indexes of the token
    /// that is swapped from (FROM) and the token that is swapped to (TO).
    /// This function is used as a helper function to calculate how much TO token
    /// the user should receive on swap.
    /// @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432.
    /// @param _x The new total amount of FROM token.
    /// @return y The amount of TO token that should remain in the pool.
    function _getY(uint _x, uint _d) private view returns (uint _y) {
        //uint _c = (_d * _d) / 2.mulUnsafeFirst(_x);
        uint _c = _d.mulDiv(_d, 2.mulUnsafeFirst(_x));
        //_c = (_c * _d) / 2.mulUnsafeFirst(N_A);
        _c = _c.mulDiv(_d, 2.mulUnsafeFirst(N_A));
        //uint _b = _x + (_d / N_A);
        uint _b = _x + _d.divUnsafeLast(N_A); /// @dev N_A will never be zero.
        uint _yPrev;
        _y = _d;
        /// @dev Iterative approximation.
        for (uint i; i < MAX_LOOP_LIMIT; ) {
            _yPrev = _y;
            //_y = (_y.mul(_y) + _c) / (_y * 2 + _b - _d);
            _y = (_y.mul(_y) + _c).div(2.mulUnsafeFirst(_y) + _b - _d);
            if (_y.within1(_yPrev)) {
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function _computeInvariant(uint _reserve0, uint _reserve1) private view returns (uint _invariant) {
        if (stable) {
            /// @dev Get D, the StableSwap invariant, based on a set of balances and a particular A.
            /// See the StableSwap paper for details.
            /// Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319.
            /// Returns the invariant, at the precision of the pool.
            unchecked {
                /// @dev It's safe because the token precision multiplier will never be zero.
                uint _adjustedReserve0 = token0PrecisionMultiplier.mulUnsafeFirst(_reserve0);
                uint _adjustedReserve1 = token1PrecisionMultiplier.mulUnsafeFirst(_reserve1);
                _invariant = _computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);
            }
        } else {
            _invariant = (_reserve0.mul(_reserve1)).sqrt();
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
                //uint _dP = mulDiv(_d.mulDiv(_d, _xp0), _d, / _xp1) / 4;
                uint _dP = (_d.mulDiv(_d, _xp0)).mulDiv(_d, _xp1);
                _prevD = _d;
                //_d = (((N_A * _s) + 2 * _dP) * _d) / ((N_A - 1) * _d + 3 * _dP);


                //_d = ((N_A.mul(_s) + 2.mul(_dP)) * _d) / ((N_A - 1).mul(_d) + 3.mul(_dP));
                /*
                _d = mulDiv(
                    N_A.mul(_s) + _dP.divUnsafe(2),
                    _d,
                    (N_A - 1).mul(_d) + 3.mulDiv(_dP, 4)
                );
                */
                _d = (
                    /// @dev `N_A` and `_s` will never be zero, so this value will never be zero.
                    (N_A.mul(_s) + _dP.divUnsafeLast(2))
                        .mulDivUnsafeFirst(
                            _d,
                            (N_A - 1).mul(_d) + 3.mulDivUnsafeBoth(_dP, 4)
                        )
                );

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

    /*
    function getVirtualPrice() external view returns (uint _virtualPrice) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        uint _invariant = _computeInvariant(_reserve0, _reserve1);
        _virtualPrice = (_invariant * 1e18) / totalSupply;
    }
    */



    

    /*
    struct SwapCache {
        uint reserve0;
        uint reserve1;
        uint amount0Out;
        uint amount1Out;
        address from;
    }

    function _swap(
        SwapCache memory _cache
    ) private returns (uint _amount0In, uint _amount1In) {
        // Get latest balances after transfer.
        (uint _balance0, uint _balance1) = _balances();
        //console.log('balance0', _balance0);
        //console.log('balance1', _balance1);

        // Get input amounts.
        _amount0In = _balance0 > _cache.reserve0 - _cache.amount0Out ? _balance0 - (_cache.reserve0 - _cache.amount0Out) : 0;
        _amount1In = _balance1 > _cache.reserve1 - _cache.amount1Out ? _balance1 - (_cache.reserve1 - _cache.amount1Out) : 0;
        require(_amount0In != 0 || _amount1In != 0, "I"); // INSUFFICIENT_INPUT_AMOUNT

        // Subtract fees from balances and check invariant.
        uint24 _swapFee = _notifySwapFee(_cache.from, _amount0In, _amount1In);
        uint _fees0 = _amount0In == 0 ? 0 : (_amount0In * _swapFee / SWAP_FEE_PRECISION);
        uint _fees1 = _amount1In == 0 ? 0 : (_amount1In * _swapFee / SWAP_FEE_PRECISION);

        address _feeRecipient = ISyncSwapFactory(factory).feeRecipient();
        if (_feeRecipient != address(0)) { // transfer protocol fees if enabled.
            //console.log('feeRecipient', _feeRecipient);
            uint8 _protocolFee = ISyncSwapFactory(factory).protocolFee();
            if (_protocolFee != 0) {
                //console.log('protocolFees0', _fees0 / _protocolFee);
                if (_fees0 > MINIMUM_FEES) {
                    TransferHelper.safeTransfer(token0, _feeRecipient, _fees0 / _protocolFee);
                }

                //console.log('protocolFees1', _fees1 / _protocolFee);
                if (_fees1 > MINIMUM_FEES) {
                    TransferHelper.safeTransfer(token1, _feeRecipient, _fees1 / _protocolFee);
                }
            }
        }

        uint _balance0Adjusted = _balance0 - _fees0;
        uint _balance1Adjusted = _balance1 - _fees1;

        
        console.log('reserve0', _cache.reserve0);
        console.log('reserve1', _cache.reserve1);
        console.log('amount0Out', _cache.amount0Out);
        console.log('amount1Out', _cache.amount1Out);
        console.log('amount0In', _amount0In);
        console.log('amount1In', _amount1In);
        console.log('swapFee', _swapFee);
        console.log('fees0', _fees0);
        console.log('fees1', _fees1);
        console.log('balance0Adjusted', _balance0Adjusted);
        console.log('balance1Adjusted', _balance1Adjusted);
        console.log('new K', _k(_balance0Adjusted, _balance1Adjusted));
        console.log('old K', _k(_cache.reserve0, _cache.reserve1));
        
        require(_k(_balance0Adjusted, _balance1Adjusted) >= _k(_cache.reserve0, _cache.reserve1), "K");

        _updateReserves(_balance0, _balance1);
    }

    function swap(
        uint _amount0Out,
        uint _amount1Out,
        address _to,
        address _from,
        bytes calldata _data
    ) external override lock {
        require(_amount0Out != 0 || _amount1Out != 0, "O"); // INSUFFICIENT_OUTPUT_AMOUNT
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        require(_amount0Out < _reserve0 && _amount1Out < _reserve1, "L"); // INSUFFICIENT_LIQUIDITY

        // Transfer tokens optimistically.
        if (_amount0Out != 0) {
            TransferHelper.safeTransfer(token0, _to, _amount0Out);
        }
        if (_amount1Out != 0) {
            TransferHelper.safeTransfer(token1, _to, _amount1Out);
        }

        // Call the callback if has data.
        if (_data.length != 0) {
            ISyncSwapCallback(_to).syncSwapCallback(msg.sender, _amount0Out, _amount1Out, _data);
        }

        (uint _amount0In, uint _amount1In) = _swap(
            SwapCache(_reserve0, _reserve1, _amount0Out, _amount1Out, _from)
        );

        emit Swap(msg.sender, _amount0In, _amount1In, _amount0Out, _amount1Out, _to);
    }
    */
}
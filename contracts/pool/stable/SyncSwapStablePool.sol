// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../libraries/ReentrancyGuard.sol";
import "../../libraries/Math.sol";
import "../../libraries/StableMath.sol";
import "../../libraries/MetadataHelper.sol";

import "../../interfaces/IPoolMaster.sol";
import "../../interfaces/vault/IVault.sol";
import "../../interfaces/factory/IPoolFactory.sol";
import "../../interfaces/pool/IStablePool.sol";

import "../SyncSwapLPToken.sol";

error Overflow();
error InsufficientLiquidityMinted();

contract SyncSwapStablePool is IStablePool, SyncSwapLPToken, ReentrancyGuard {
    using Math for uint;

    uint private constant MAXIMUM_XP = 3802571709128108338056982581425910818;
    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.

    /// @dev Pool type `2` for stable pools.
    uint16 public constant override poolType = 2;

    address public immutable override master;
    address public immutable override vault;

    address public immutable override token0;
    address public immutable override token1;

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
    constructor() {
        (bytes memory _deployData) = IPoolFactory(msg.sender).getDeployData();
        (address _token0, address _token1, uint _token0PrecisionMultiplier, uint _token1PrecisionMultiplier) = abi.decode(
            _deployData, (address, address, uint, uint)
        );
        address _master = IPoolFactory(msg.sender).master();

        master = _master;
        vault = IPoolMaster(_master).vault();
        (token0, token1, token0PrecisionMultiplier, token1PrecisionMultiplier) = (
            _token0, _token1, _token0PrecisionMultiplier, _token1PrecisionMultiplier
        );

        // try to set symbols for the LP token
        (bool _success0, string memory _symbol0) = MetadataHelper.getSymbol(_token0);
        (bool _success1, string memory _symbol1) = MetadataHelper.getSymbol(_token1);
        if (_success0 && _success1) {
            _initializeMetadata(
                string(abi.encodePacked("SyncSwap ", _symbol0, "/", _symbol1, " Stable LP")),
                string(abi.encodePacked(_symbol0, "/", _symbol1, " sSLP"))
            );
        } else {
            _initializeMetadata(
                "SyncSwap Stable LP",
                "sSLP"
            );
        }
    }

    function getAssets() external view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(bytes calldata _data) external override nonReentrant returns (uint _liquidity) {
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
        uint _oldInvariant = _computeInvariant(_reserve0, _reserve1);
        (bool _feeOn, uint _totalSupply) = _mintProtocolFee(0, 0, _oldInvariant);

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
    function burn(bytes calldata _data) external override nonReentrant returns (TokenAmount[] memory _amounts) {
        (address _to, uint8 _withdrawMode) = abi.decode(_data, (address, uint8));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply) = _mintProtocolFee(_balance0, _balance1, 0);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;
        //require(_amount0 != 0 || _amount1 != 0); // unchecked to save gas, should be done through router.

        // Burns liquidity and transfers pool tokens.
        _burn(address(this), _liquidity);
        _transferTokens(token0, _to, _amount0, _withdrawMode);
        _transferTokens(token1, _to, _amount1, _withdrawMode);

        // Update reserves and last invariant with up-to-date balances (after transfers).
        /// @dev Using counterfactuals balances here to save gas.
        /// Cannot underflow because amounts are lesser figures derived from balances.
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
    function burnSingle(bytes calldata _data) external override nonReentrant returns (uint _amountOut) {
        (address _tokenOut, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply) = _mintProtocolFee(_balance0, _balance1, 0);

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
            _transferTokens(token1, _to, _amount1, _withdrawMode);
            _amountOut = _amount1;
            _amount0 = 0;
            _balance1 -= _amount1;
        } else {
            // Swap `token1` for `token0`.
            require(_tokenOut == token0); // ensures to prevent from messing up the pool with bad parameters.
            _amount0 += _getAmountOut(_amount1, _balance0 - _amount0, _balance1 - _amount1, false);
            _transferTokens(token0, _to, _amount0, _withdrawMode);
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
    function swap(bytes calldata _data) external override nonReentrant returns (uint _amountOut) {
        (address _tokenIn, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        // Calculates output amount, update context values and emit event.
        uint _amountIn;
        address _tokenOut;
        if (_tokenIn == token0) {
            _tokenOut = token1;
            _amountIn = _balance0 - _reserve0;
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, true);
            _balance1 -= _amountOut;

            emit Swap(msg.sender, _amountIn, 0, 0, _amountOut, _to); // emit here to avoid checking direction 
        } else {
            //require(_tokenIn == token1);
            _tokenOut = token0;
            _amountIn = _balance1 - reserve1;
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, false);
            _balance0 -= _amountOut;

            emit Swap(msg.sender, 0, _amountIn, _amountOut, 0, _to);
        }

        // Checks overflow.
        if (_balance0 * token0PrecisionMultiplier > MAXIMUM_XP) {
            revert Overflow();
        }
        if (_balance1 * token1PrecisionMultiplier > MAXIMUM_XP) {
            revert Overflow();
        }

        // Transfers output tokens.
        _transferTokens(_tokenOut, _to, _amountOut, _withdrawMode);

        // Update reserves with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);
    }

    function getSwapFee() public view override returns (uint24 _swapFee) {
        _swapFee = IPoolMaster(master).getSwapFee(address(this));
    }

    function getProtocolFee() public view override returns (uint24 _protocolFee) {
        _protocolFee = IPoolMaster(master).protocolFee(poolType);
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
            _token1Fee = (getSwapFee() * (_amount1 - _amount1Optimal)) / (2 * MAX_FEE);
        } else {
            uint _amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            _token0Fee = (getSwapFee() * (_amount0 - _amount0Optimal)) / (2 * MAX_FEE);
        }
    }

    function _mintProtocolFee(uint _reserve0, uint _reserve1, uint _invariant) private returns (bool _feeOn, uint _totalSupply) {
        _totalSupply = totalSupply;

        address _feeRecipient = IPoolMaster(master).feeRecipient();
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

    function getAmountIn(address _tokenOut, uint _amountOut) external view override returns (uint _finalAmountIn) {
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
            unchecked {
                uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                uint _feeDeductedAmountIn = _amountIn - (_amountIn * getSwapFee()) / MAX_FEE;
                uint _d = StableMath.computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                if (_token0In) {
                    uint _x = _adjustedReserve0 + (_feeDeductedAmountIn * token0PrecisionMultiplier);
                    uint _y = StableMath.getY(_x, _d);
                    _dy = _adjustedReserve1 - _y - 1;
                    _dy /= token1PrecisionMultiplier;
                } else {
                    uint _x = _adjustedReserve1 + (_feeDeductedAmountIn * token1PrecisionMultiplier);
                    uint _y = StableMath.getY(_x, _d);
                    _dy = _adjustedReserve0 - _y - 1;
                    _dy /= token0PrecisionMultiplier;
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
            unchecked {
                uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                uint _d = StableMath.computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                if (_token0Out) {
                    uint _y = _adjustedReserve0 - (_amountOut * token0PrecisionMultiplier);
                    if (_y <= 1) {
                        return 1;
                    }
                    uint _x = StableMath.getY(_y, _d);
                    _dx = MAX_FEE * (_x - _adjustedReserve1) / (MAX_FEE - getSwapFee()) + 1;
                    _dx /= token1PrecisionMultiplier;
                } else {
                    uint _y = _adjustedReserve1 - (_amountOut * token1PrecisionMultiplier);
                    if (_y <= 1) {
                        return 1;
                    }
                    uint _x = StableMath.getY(_y, _d);
                    _dx = MAX_FEE * (_x - _adjustedReserve0) / (MAX_FEE - getSwapFee()) + 1;
                    _dx /= token0PrecisionMultiplier;
                }
            }
        }
    }

    function _computeInvariant(uint _reserve0, uint _reserve1) private view returns (uint _invariant) {
        /// @dev Get D, the StableSwap invariant, based on a set of balances and a particular A.
        /// See the StableSwap paper for details.
        /// Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319.
        /// Returns the invariant, at the precision of the pool.
        unchecked {
            uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            if (_adjustedReserve0 > MAXIMUM_XP) {
                revert Overflow();
            }
            if (_adjustedReserve1 > MAXIMUM_XP) {
                revert Overflow();
            }
            _invariant = StableMath.computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);
        }
    }
}
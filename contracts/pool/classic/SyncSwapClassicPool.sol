// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../../libraries/ReentrancyGuard.sol";
import "../../libraries/Math.sol";
import "../../libraries/MetadataHelper.sol";

import "../../interfaces/vault/IVault.sol";
import "../../interfaces/master/IPoolMaster.sol";
import "../../interfaces/factory/IPoolFactory.sol";
import "../../interfaces/pool/IClassicPool.sol";

import "../SyncSwapLPToken.sol";

error Overflow();
error InsufficientLiquidityMinted();

contract SyncSwapClassicPool is IClassicPool, SyncSwapLPToken, ReentrancyGuard {
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

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(bytes calldata _data, address _sender) external override nonReentrant returns (uint _liquidity) {
        address _to = abi.decode(_data, (address));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        uint _newInvariant = _computeInvariant(_balance0, _balance1);
        uint _amount0 = _balance0 - _reserve0;
        uint _amount1 = _balance1 - _reserve1;
        //require(_amount0 != 0 && _amount1 != 0);

        {
        // Adds mint fee to reserves (applies to invariant increase) if unbalanced.
        (uint _fee0, uint _fee1) = _unbalancedMintFee(_getSwapFee(_sender), _amount0, _amount1, _reserve0, _reserve1);
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
        //require(_amount0 != 0 || _amount1 != 0);

        // Burns liquidity and transfers pool tokens.
        _burn(address(this), _liquidity);
        _transferTokens(token0, _to, _amount0, _withdrawMode);
        _transferTokens(token1, _to, _amount1, _withdrawMode);

        // Updates reserves and last invariant with up-to-date balances (after transfers).
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
    function burnSingle(bytes calldata _data, address _sender) external override nonReentrant returns (uint _amountOut) {
        (address _tokenOut, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply) = _mintProtocolFee(_balance0, _balance1, 0);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;

        // Burns liquidity.
        _burn(address(this), _liquidity);

        // Gets swap fee for the sender.
        uint _swapFee = _getSwapFee(_sender);

        // Swaps one token for another, transfers desired tokens, and update context values.
        /// @dev Calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped from one token for another.
        if (_tokenOut == token1) {
            // Swap `token0` for `token1`.
            _amount1 += _getAmountOut(_swapFee, _amount0, _balance0 - _amount0, _balance1 - _amount1, true);
            _transferTokens(token1, _to, _amount1, _withdrawMode);
            _amountOut = _amount1;
            _amount0 = 0;
            _balance1 -= _amount1;
        } else {
            // Swap `token1` for `token0`.
            //require(_tokenOut == token0);
            _amount0 += _getAmountOut(_swapFee, _amount1, _balance0 - _amount0, _balance1 - _amount1, false);
            _transferTokens(token0, _to, _amount0, _withdrawMode);
            _amountOut = _amount0;
            _amount1 = 0;
            _balance0 -= _amount0;
        }

        // Updates reserves and last invariant with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);

        if (_feeOn) {
            invariantLast = _computeInvariant(_balance0, _balance1);
        }

        emit Burn(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    struct SwapContext {
        uint swapFee;
        uint amountIn;
        address tokenOut;
    }

    /// @dev Swaps one token for another - should be called via the router after transferring input tokens.
    /// The router should ensure that sufficient output tokens are received.
    function swap(bytes calldata _data, address _sender) external override nonReentrant returns (uint _amountOut) {
        (address _tokenIn, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        SwapContext memory context; // use struct to avoid stack too deep errors

        // Gets swap fee for the sender.
        context.swapFee = _getSwapFee(_sender);

        // Calculates output amount, update context values and emit event.
        if (_tokenIn == token0) {
            context.tokenOut = token1;
            context.amountIn = _balance0 - _reserve0;

            _amountOut = _getAmountOut(context.swapFee, context.amountIn, _reserve0, _reserve1, true);
            _balance1 -= _amountOut;

            emit Swap(msg.sender, context.amountIn, 0, 0, _amountOut, _to); // emit here to avoid checking direction 
        } else {
            //require(_tokenIn == token1);
            context.tokenOut = token0;
            context.amountIn = _balance1 - reserve1;

            _amountOut = _getAmountOut(context.swapFee, context.amountIn, _reserve0, _reserve1, false);
            _balance0 -= _amountOut;

            emit Swap(msg.sender, 0, context.amountIn, _amountOut, 0, _to);
        }

        // Checks overflow.
        if (_balance0 > type(uint128).max) {
            revert Overflow();
        }
        if (_balance1 > type(uint128).max) {
            revert Overflow();
        }

        // Transfers output tokens.
        _transferTokens(context.tokenOut, _to, _amountOut, _withdrawMode);

        // Updates reserves with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);
    }

    /// @dev Returns swap fee for sender considering the forwarder.
    function _getSwapFee(address _sender) private view returns (uint24 _swapFee) {
        // Only reports the sender from registered forwarders.
        _swapFee = IPoolMaster(master).getSwapFee(
            address(this),
            IPoolMaster(master).isForwarder(msg.sender) ? _sender : address(0)
        );
    }

    function getSwapFee(address _sender) external view override returns (uint24 _swapFee) {
        _swapFee = IPoolMaster(master).getSwapFee(address(this), _sender);
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

    /// @dev This fee is charged to cover for the swap fee when users add unbalanced liquidity.
    function _unbalancedMintFee(
        uint _swapFee,
        uint _amount0,
        uint _amount1,
        uint _reserve0,
        uint _reserve1
    ) private pure returns (uint _token0Fee, uint _token1Fee) {
        if (_reserve0 == 0 || _reserve1 == 0) {
            return (0, 0);
        }
        uint _amount1Optimal = (_amount0 * _reserve1) / _reserve0;
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

    function getAmountOut(address _tokenIn, uint _amountIn, address _sender) external view override returns (uint _finalAmountOut) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        _finalAmountOut = _getAmountOut(_getSwapFee(_sender), _amountIn, _reserve0, _reserve1, _tokenIn == token0);
    }

    function getAmountIn(address _tokenOut, uint _amountOut, address _sender) external view override returns (uint _finalAmountIn) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        _finalAmountIn = _getAmountIn(_getSwapFee(_sender), _amountOut, _reserve0, _reserve1, _tokenOut == token0);
    }

    function _getAmountOut(
        uint _swapFee,
        uint _amountIn,
        uint _reserve0,
        uint _reserve1,
        bool _token0In
    ) private pure returns (uint _dy) {
        if (_amountIn == 0) {
            _dy = 0;
        } else {
            uint _amountInWithFee = _amountIn * (MAX_FEE - _swapFee);
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
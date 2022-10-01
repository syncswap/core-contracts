// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import './libraries/Lock.sol';
import './libraries/Math.sol';
import './libraries/SwapMath.sol';
import './libraries/TransferHelper.sol';
import './interfaces/IPool.sol';
import './interfaces/IERC20.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IUniswapV2Callee.sol';
import './PoolERC20.sol';

contract Pool is IPool, PoolERC20, Lock {

    /// @dev Minimum liquidity to lock on the first liquidity provision.
    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant SWAP_FEE_PRECISION = 1e6;

    address public immutable override factory;
    bool public immutable override stable;
    address public immutable override token0;
    address public immutable override token1;

    uint private immutable decimals0;
    uint private immutable decimals1;

    uint public override reserve0;
    uint public override reserve1;

    /// @dev reserve0 * reserve1, as of immediately after the most recent liquidity event.
    uint public override kLast;

    constructor(address _token0, address _token1, bool _stable, uint _decimals0, uint _decimals1) {
        (factory, token0, token1, stable, decimals0, decimals1) = (msg.sender, _token0, _token1, _stable, _decimals0, _decimals1);
    }

    function _updateReserves(uint _balance0, uint _balance1) private {
        (reserve0, reserve1) = (_balance0, _balance1);
        emit Sync(_balance0, _balance1);
    }

    /// @dev If fee is on, mint liquidity equivalent to 1/(protocolFee) of the growth in sqrt(k).
    function _mintProtocolFee(uint _reserve0, uint _reserve1) private returns (bool _feeOn) {
        address _feeRecipient = IPoolFactory(factory).feeRecipient();
        _feeOn = _feeRecipient != address(0);

        uint _kLast = kLast;
        if (_feeOn) {
            if (_kLast != 0) {
                uint _rootK = Math.sqrt(_reserve0 * _reserve1);
                uint _rootKLast = Math.sqrt(_kLast);
                if (_rootK > _rootKLast) {
                    uint8 _protocolFee = IPoolFactory(factory).protocolFee();
                    uint _numerator = totalSupply * (_rootK - _rootKLast);
                    uint _denominator = _rootK * (_protocolFee - 1) + _rootKLast;
                    uint _liquidity = _numerator / _denominator;
                    if (_liquidity != 0) {
                        _mint(_feeRecipient, _liquidity);
                    }
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _balances() private view returns (uint, uint) {
        return (IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    function mint(address _to) external override lock returns (uint _liquidity) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();
        (uint _amount0, uint _amount1) = (_balance0 - _reserve0, _balance1 - reserve1);

        // Try mint protocol fee.
        bool _feeOn = _mintProtocolFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // must be defined here since this can change on minting protocol fee.

        // Calculate the liquidity to mint.
        if (_totalSupply == 0) {
            _liquidity = Math.sqrt(_amount0 * _amount1) - MINIMUM_LIQUIDITY;

            // Permanently lock the minimum liquidity.
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            _liquidity = Math.min(_amount0 * _totalSupply / _reserve0, _amount1 * _totalSupply / _reserve1);
        }

        // Mint the liquidity for recipient.
        require(_liquidity != 0, 'M'); // INSUFFICIENT_LIQUIDITY_MINTED
        _mint(_to, _liquidity);

        _updateReserves(_balance0, _balance1);
        if (_feeOn) {
            kLast = _reserve0 * _reserve1;
        }
        emit Mint(msg.sender, _amount0, _amount1);
    }

    function burn(address _to) external override lock returns (uint _amount0, uint _amount1) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Try mint protocol fee.
        bool _feeOn = _mintProtocolFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // must be defined here since this can change on minting protocol fee.

        // Calculate the amounts of pool tokens, use balances ensures pro-rata distribution.
        _amount0 = _liquidity * _balance0 / _totalSupply;
        _amount1 = _liquidity * _balance1 / _totalSupply;
        require(_amount0 != 0 || _amount1 != 0, 'B'); // INSUFFICIENT_LIQUIDITY_BURNED

        // Burn the liquidity and transfer pool tokens.
        _burn(address(this), _liquidity);
        TransferHelper.safeTransfer(token0, _to, _amount0);
        TransferHelper.safeTransfer(token1, _to, _amount1);

        // Get latest balances after transfer.
        (_balance0, _balance1) = _balances();
        _updateReserves(_balance0, _balance1);
        if (_feeOn) {
            kLast = _reserve0 * _reserve1;
        }
        emit Burn(msg.sender, _amount0, _amount1, _to);
    }

    function _swapFee() private view returns (uint24) {
        return IPoolFactory(factory).swapFee(address(this));
    }

    function swap(uint _amount0Out, uint _amount1Out, address _to, bytes calldata data) external override lock {
        require(_amount0Out != 0 || _amount1Out != 0, 'O'); // INSUFFICIENT_OUTPUT_AMOUNT
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        require(_amount0Out < _reserve0 && _amount1Out < _reserve1, 'L'); // INSUFFICIENT_LIQUIDITY

        uint _balance0; uint _balance1;
        {
        // Transfer tokens optimistically.
        if (_amount0Out != 0) {
            TransferHelper.safeTransfer(token0, _to, _amount0Out);
        }
        if (_amount1Out != 0) {
            TransferHelper.safeTransfer(token1, _to, _amount1Out);
        }

        // Call the callback if has data.
        if (data.length != 0) {
            IUniswapV2Callee(_to).uniswapV2Call(msg.sender, _amount0Out, _amount1Out, data);
        }

        // Get latest balances after transfer.
        (_balance0, _balance1) = _balances();
        }

        // Get input amounts.
        uint _amount0In = _balance0 > _reserve0 - _amount0Out ? _balance0 - (_reserve0 - _amount0Out) : 0;
        uint _amount1In = _balance1 > _reserve1 - _amount1Out ? _balance1 - (_reserve1 - _amount1Out) : 0;
        require(_amount0In != 0 || _amount1In != 0, 'I'); // INSUFFICIENT_INPUT_AMOUNT

        {
        // Subtract fees from balances and check invariant.
        uint24 __swapFee = _swapFee();
        uint _balance0Adjusted = _balance0 - (_amount0In * __swapFee / SWAP_FEE_PRECISION);
        uint _balance1Adjusted = _balance1 - (_amount1In * __swapFee / SWAP_FEE_PRECISION);
        require(_k(_balance0Adjusted, _balance1Adjusted) >= _k(_reserve0, _reserve1), 'K');
        }

        _updateReserves(_balance0, _balance1);
        emit Swap(msg.sender, _amount0In, _amount1In, _amount0Out, _amount1Out, _to);
    }

    function _k(uint _x, uint _y) private view returns (uint) {
        return stable ? SwapMath.stableK(_x, _y, decimals0, decimals1) : _x * _y;
    }
}
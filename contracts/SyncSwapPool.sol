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

import 'hardhat/console.sol';

contract SyncSwapPool is ISyncSwapPool, SyncSwapERC20, Lock {

    /// @dev Minimum liquidity to lock on the first liquidity provision.
    uint private constant MINIMUM_LIQUIDITY = 1000;

    /// @dev Minimum fees to transfer protocol fee fraction.
    uint private constant MINIMUM_FEES = 1000;

    uint private constant SWAP_FEE_PRECISION = 1e6;

    address public immutable override factory;
    bool public immutable override stable;
    address public immutable override token0;
    address public immutable override token1;

    uint public immutable override decimals0;
    uint public immutable override decimals1;

    uint public override reserve0;
    uint public override reserve1;

    constructor(address _token0, address _token1, bool _stable, uint _decimals0, uint _decimals1) {
        (factory, token0, token1, stable, decimals0, decimals1) = (
            msg.sender, _token0, _token1, _stable, _decimals0, _decimals1
        );
    }

    function _updateReserves(uint _balance0, uint _balance1) private {
        (reserve0, reserve1) = (_balance0, _balance1);
        emit Sync(_balance0, _balance1);
    }

    function _balances() private view returns (uint, uint) {
        return (IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }

    function _notifySwapFee(address _from, uint _amount0In, uint _amount1In) private returns (uint24 _swapFee) {
        _swapFee = ISyncSwapFactory(factory).notifySwapFee(address(this), msg.sender, _from, _amount0In, _amount1In);
    }

    function mint(address _to) external override lock returns (uint _liquidity) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();
        (uint _amount0, uint _amount1) = (_balance0 - _reserve0, _balance1 - reserve1);
        uint _totalSupply = totalSupply;

        // Calculate the liquidity to mint.
        if (_totalSupply == 0) {
            _liquidity = Math.sqrt(_amount0 * _amount1) - MINIMUM_LIQUIDITY;

            // Permanently lock the minimum liquidity.
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            _liquidity = Math.min(_amount0 * _totalSupply / _reserve0, _amount1 * _totalSupply / _reserve1);
        }

        // Mint the liquidity for recipient.
        require(_liquidity != 0, "M"); // INSUFFICIENT_LIQUIDITY_MINTED
        _mint(_to, _liquidity);

        _updateReserves(_balance0, _balance1);
        emit Mint(msg.sender, _amount0, _amount1);
    }

    function burn(address _to) external override lock returns (uint _amount0, uint _amount1) {
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];
        uint _totalSupply = totalSupply;

        // Calculate the amounts of pool tokens, use balances ensures pro-rata distribution.
        _amount0 = _liquidity * _balance0 / _totalSupply;
        _amount1 = _liquidity * _balance1 / _totalSupply;
        require(_amount0 != 0 || _amount1 != 0, "ILB"); // INSUFFICIENT_LIQUIDITY_BURNED

        // Burn the liquidity and transfer pool tokens.
        _burn(address(this), _liquidity);
        TransferHelper.safeTransfer(token0, _to, _amount0);
        TransferHelper.safeTransfer(token1, _to, _amount1);

        // Get latest balances after transfer.
        (_balance0, _balance1) = _balances();
        _updateReserves(_balance0, _balance1);
        emit Burn(msg.sender, _amount0, _amount1, _to);
    }

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

        /*
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
        */
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

    function _k(uint _x, uint _y) private view returns (uint) {
        return stable ? SyncSwapLibrary.getKStable(_x, _y, decimals0, decimals1) : _x * _y;
    }
}
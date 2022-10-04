// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/ISyncSwapPool.sol";
import "./interfaces/ISwapFeeProvider.sol";
import "./interfaces/ISyncSwapFactory.sol";
import "./libraries/Ownable.sol";
import "./SyncSwapPool.sol";

/// @notice Canonical factory to deploy pools and control over fees.
contract SyncSwapFactory is ISyncSwapFactory, Ownable {
    /// @inheritdoc ISyncSwapFactory
    address public override feeRecipient;
    /// @inheritdoc ISyncSwapFactory
    uint8 public override protocolFee = 5; // 1/5
    /// @inheritdoc ISyncSwapFactory
    address public swapFeeProvider;

    /// @inheritdoc ISyncSwapFactory
    mapping(address => mapping(address => mapping(bool => address))) public override getPair;
    /// @inheritdoc ISyncSwapFactory
    mapping(address => bool) public override isPair;
    /// @inheritdoc ISyncSwapFactory
    address[] public override allPairs;

    constructor(address _feeRecipient, address _swapFeeProvider) {
        feeRecipient = _feeRecipient;
        swapFeeProvider = _swapFeeProvider;
    }

    /// @inheritdoc ISyncSwapFactory
    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    /// @inheritdoc ISyncSwapFactory
    function getSwapFee(
        address _pool,
        address _sender,
        address _from,
        uint _amount0In,
        uint _amount1In
    ) external override view returns (uint24) {
        address _swapFeeProvider = swapFeeProvider;
        return _swapFeeProvider == address(0) ? 0 : (
            ISwapFeeProvider(swapFeeProvider).getSwapFee(_pool, _sender, _from, _amount0In, _amount1In)
        );
    }

    /// @inheritdoc ISyncSwapFactory
    function notifySwapFee(
        address _pool,
        address _sender,
        address _from,
        uint _amount0In,
        uint _amount1In
    ) external override returns (uint24) {
        address _swapFeeProvider = swapFeeProvider;
        return _swapFeeProvider == address(0) ? 0 : (
            ISwapFeeProvider(swapFeeProvider).notifySwapFee(_pool, _sender, _from, _amount0In, _amount1In)
        );
    }

    /// @inheritdoc ISyncSwapFactory
    function createPair(address _tokenA, address _tokenB, bool _stable) external override returns (address _pair) {
        require(_tokenA != _tokenB, "Identical addresses");
        (address _token0, address _token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(_token0 != address(0), "Invalid address");
        require(getPair[_token0][_token1][_stable] == address(0), "Pool exists");

        uint _decimals0 = 10 ** IERC20(_token0).decimals();
        uint _decimals1 = 10 ** IERC20(_token1).decimals();
        _pair = address(new SyncSwapPool(_token0, _token1, _stable, _decimals0, _decimals1));

        getPair[_token0][_token1][_stable] = _pair;
        getPair[_token1][_token0][_stable] = _pair; // populate mapping in the reverse direction
        allPairs.push(_pair);
        isPair[_pair] = true;
        emit PairCreated(_token0, _token1, _stable, _pair, allPairs.length);
    }

    /// @inheritdoc ISyncSwapFactory
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc ISyncSwapFactory
    function setProtocolFee(uint8 _protocolFee) external override onlyOwner {
        require(_protocolFee > 1, "Invalid protocol fee");
        protocolFee = _protocolFee;
    }

    /// @inheritdoc ISyncSwapFactory
    function setSwapFeeProvider(address _swapFeeProvider) external override onlyOwner {
        swapFeeProvider = _swapFeeProvider;
    }
}
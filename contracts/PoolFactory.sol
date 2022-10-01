// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import './interfaces/IPoolFactory.sol';
import './interfaces/IERC20.sol';
import './interfaces/IPool.sol';
import './Pool.sol';

contract PoolFactory is IPoolFactory {
    uint24 private constant MAXIMUM_SWAP_FEE = 1e5; // 10%

    address public override owner;
    address public override pendingOwner;

    address public override feeRecipient;
    uint8 public override protocolFee;
    uint24 public override defaultSwapFeeNonstable = 3000; // 0.3%
    uint24 public override defaultSwapFeeStable = 3000; // 0.3%

    struct CustomSwapFee {
        bool exists;
        uint24 swapFee;
    }
    mapping(address => CustomSwapFee) public override customSwapFee;

    mapping(address => mapping(address => mapping(bool => address))) public override getPair;
    mapping(address => bool) public override isPair;
    address[] public override allPairs;

    constructor() {
        owner = msg.sender;
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function swapFee(address _pool) external override view returns (uint24) {
        CustomSwapFee memory _customSwapFee = customSwapFee[_pool];
        if (_customSwapFee.exists) {
            return _customSwapFee.swapFee;
        } else {
            return IPool(_pool).stable() ? defaultSwapFeeStable : defaultSwapFeeNonstable;
        }
    }

    function createPair(address _tokenA, address _tokenB, bool _stable) external override returns (address _pair) {
        require(_tokenA != _tokenB);
        (address _token0, address _token1) = _tokenA < _tokenB ? (_tokenA, _tokenB) : (_tokenB, _tokenA);
        require(_token0 != address(0));
        require(getPair[_token0][_token1][_stable] == address(0));

        uint _decimals0 = 10 ** IERC20(_token0).decimals();
        uint _decimals1 = 10 ** IERC20(_token1).decimals();
        _pair = address(new Pool(_token0, _token1, _stable, _decimals0, _decimals1));

        getPair[_token0][_token1][_stable] = _pair;
        getPair[_token1][_token0][_stable] = _pair; // populate mapping in the reverse direction
        allPairs.push(_pair);
        isPair[_pair] = true;
        emit PairCreated(_token0, _token1, _pair, allPairs.length);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function setPendingOwner(address _pendingOwner) external override onlyOwner {
        pendingOwner = _pendingOwner;
    }

    function acceptOwner() external {
        address _pendingOwner = pendingOwner;
        require(msg.sender == _pendingOwner);
        owner = _pendingOwner;
        pendingOwner = address(0);
    }

    function setProtocolFee(uint8 _protocolFee) external override onlyOwner {
        require(_protocolFee > 1);
        protocolFee = _protocolFee;
    }

    function setDefaultSwapFeeNonstable(uint24 _defaultSwapFeeNonstable) external override onlyOwner {
        require(_defaultSwapFeeNonstable <= MAXIMUM_SWAP_FEE);
        defaultSwapFeeNonstable = _defaultSwapFeeNonstable;
    }

    function setDefaultSwapFeeStable(uint24 _defaultSwapFeeStable) external override onlyOwner {
        require(_defaultSwapFeeStable <= MAXIMUM_SWAP_FEE);
        defaultSwapFeeStable = _defaultSwapFeeStable;
    }

    function setCustomSwapFee(address _pool, uint24 _customSwapFee) external override onlyOwner {
        require(_customSwapFee <= MAXIMUM_SWAP_FEE);
        customSwapFee[_pool] = CustomSwapFee(true, _customSwapFee);
    }

    function removeCustomSwapFee(address _pool) external override onlyOwner {
        delete customSwapFee[_pool];
    }
}
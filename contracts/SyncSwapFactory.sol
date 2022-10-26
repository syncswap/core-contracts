// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./interfaces/IBasePool.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ISyncSwapFactory.sol";
import "./libraries/Ownable.sol";
import "./SyncSwapPool.sol";

error IdenticalTokens();
error PoolExists();
error InvalidFee();

/// @notice Canonical factory to deploy pools and control over fees.
contract SyncSwapFactory is ISyncSwapFactory, Ownable {

    uint8 private POOL_PRECISION_DECIMALS = 18;
    uint private STABLE_POOL_A = 400000;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.
    uint private constant MAX_SWAP_FEE = 3000; /// @dev 3%.

    uint24 public override defaultSwapFeeVolatile = 300; /// @dev 0.3%.
    uint24 public override defaultSwapFeeStable = 100; /// @dev 0.1%.
    mapping(address => CustomSwapFee) public override customSwapFeeByPool;

    address public immutable vault;

    /// @inheritdoc ISyncSwapFactory
    address public override feeRecipient;
    /// @inheritdoc ISyncSwapFactory
    uint24 public override protocolFee = 30000; /// @dev 30%.

    /// @inheritdoc ISyncSwapFactory
    mapping(address => mapping(address => mapping(bool => address))) public override getPool;
    /// @inheritdoc ISyncSwapFactory
    mapping(address => bool) public override isPool;
    /// @inheritdoc ISyncSwapFactory
    address[] public override allPools;

    constructor(address _vault, address _feeRecipient) {
        require(_vault != address(0));
        vault = _vault;
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc ISyncSwapFactory
    function allPoolsLength() external override view returns (uint) {
        return allPools.length;
    }

    /// @inheritdoc ISyncSwapFactory
    function getSwapFee(address _pool) external override view returns (uint24) {
        CustomSwapFee memory _customSwapFee = customSwapFeeByPool[_pool];
        if (_customSwapFee.exists) {
            return _customSwapFee.swapFee;
        } else {
            if (IBasePool(_pool).A() == 0) {
                return defaultSwapFeeVolatile;
            } else {
                return defaultSwapFeeStable;
            }
        }
    }

    /// @inheritdoc ISyncSwapFactory
    function createPool(address _tokenA, address _tokenB, bool _stable) external override returns (address _pool) {
        if (_tokenA == _tokenB) {
            revert IdenticalTokens();
        }
        if (getPool[_tokenA][_tokenB][_stable] != address(0)) {
            revert PoolExists();
        }
        if (_tokenB < _tokenA) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }

        // Creates the pool.
        uint _token0PrecisionMultiplier = _stable ? 10 ** (POOL_PRECISION_DECIMALS - IERC20(_tokenA).decimals()) : 1;
        uint _token1PrecisionMultiplier = _stable ? 10 ** (POOL_PRECISION_DECIMALS - IERC20(_tokenB).decimals()) : 1;
        _pool = address(new SyncSwapPool(
            vault,
            _tokenA,
            _tokenB,
            _stable ? STABLE_POOL_A : 0,
            _token0PrecisionMultiplier,
            _token1PrecisionMultiplier
        ));

        getPool[_tokenA][_tokenB][_stable] = _pool;
        getPool[_tokenB][_tokenA][_stable] = _pool; // populate mapping in the reverse direction
        allPools.push(_pool);
        isPool[_pool] = true;

        emit PoolCreated(_tokenA, _tokenB, _stable, _pool, allPools.length);
    }

    /// @inheritdoc ISyncSwapFactory
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc ISyncSwapFactory
    function setProtocolFee(uint24 _protocolFee) external override onlyOwner {
        if (_protocolFee > MAX_FEE) revert InvalidFee();
        protocolFee = _protocolFee;
    }

    function setDefaultSwapFeeVolatile(uint24 _swapFee) external override onlyOwner {
        if (_swapFee > MAX_SWAP_FEE) revert InvalidFee();
        defaultSwapFeeVolatile = _swapFee;
        emit UpdateDefaultSwapFeeVolatile(_swapFee);
    }

    function setDefaultSwapFeeStable(uint24 _swapFee) external override onlyOwner {
        if (_swapFee > MAX_SWAP_FEE) revert InvalidFee();
        defaultSwapFeeStable = _swapFee;
        emit UpdateDefaultSwapFeeStable(_swapFee);
    }

    function setCustomSwapFeeForPool(address _pool, uint24 _swapFee) external override onlyOwner {
        if (_swapFee > MAX_SWAP_FEE) revert InvalidFee();
        customSwapFeeByPool[_pool] = CustomSwapFee(true, _swapFee);
        emit UpdateCustomSwapFee(_pool, true, _swapFee);
    }

    function removeCustomSwapFeeForPool(address _pool) external override onlyOwner {
        delete customSwapFeeByPool[_pool];
        emit UpdateCustomSwapFee(_pool, false, 0);
    }
}
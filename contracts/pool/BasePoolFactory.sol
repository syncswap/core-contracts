// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "../interfaces/IBasePoolFactory.sol";

import "../libraries/Ownable.sol";

error IdenticalTokens();
error PoolExists();
error InvalidFee();

/// @notice Canonical factory to deploy pools and control over fees.
abstract contract BasePoolFactory is IBasePoolFactory, Ownable {

    /*
    uint private constant MAX_FEE = 1e5; /// @dev 100%.
    uint private constant MAX_SWAP_FEE = 3000; /// @dev 3%.

    address public immutable vault;

    uint24 public override defaultSwapFee; /// @dev `300` for 0.3%.
    mapping(address => CustomSwapFee) public override customSwapFee;

    /// @inheritdoc IBasePoolFactory
    address public override feeRecipient;
    /// @inheritdoc IBasePoolFactory
    uint24 public override protocolFee; /// @dev `30000` for 30%.

    /// @inheritdoc IBasePoolFactory
    mapping(address => mapping(address => address)) public override getPool;
    /// @inheritdoc IBasePoolFactory
    mapping(address => bool) public override isPool;
    /// @inheritdoc IBasePoolFactory
    address[] public override pools;
    */

    address public immutable registry;

    mapping(address => mapping(address => address)) public override getPool;

    bytes internal cachedDeployData;

    constructor(address _registry) {
        registry = _registry;
    }

    function getDeployData() external view override returns (bytes memory deployData) {
        deployData = cachedDeployData;
    }

    /*
    /// @inheritdoc IBasePoolFactory
    function poolsLength() external override view returns (uint) {
        return pools.length;
    }

    /// @inheritdoc IBasePoolFactory
    function getSwapFee(address pool) external override view returns (uint24) {
        CustomSwapFee memory _customSwapFee = customSwapFee[pool];
        if (_customSwapFee.exists) {
            return _customSwapFee.fee;
        } else {
            return defaultSwapFee;
        }
    }
    */

    function createPool(bytes calldata _data) external override returns (address pool) {
        (address _tokenA, address _tokenB) = abi.decode(_data, (address, address));

        if (_tokenA == _tokenB) {
            revert IdenticalTokens();
        }
        if (getPool[_tokenA][_tokenB] != address(0)) {
            revert PoolExists();
        }
        if (_tokenB < _tokenA) {
            (_tokenA, _tokenB) = (_tokenB, _tokenA);
        }

        // Create the pool.
        pool = _deployPool(_tokenA, _tokenB);

        // Populate the pool.
        getPool[_tokenA][_tokenB] = pool;
        getPool[_tokenB][_tokenA] = pool; // populate mapping in the reverse direction.
        //isPool[pool] = true;
        //pools.push(pool);

        emit PoolCreated(_tokenA, _tokenB, pool, pools.length);
    }

    function _deployPool(address tokenA, address tokenB) internal virtual returns (address) {}

    /*
    /// @inheritdoc IBasePoolFactory
    function setFeeRecipient(address _feeRecipient) external override onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /// @inheritdoc IBasePoolFactory
    function setProtocolFee(uint24 _protocolFee) external override onlyOwner {
        if (_protocolFee > MAX_FEE) revert InvalidFee();
        protocolFee = _protocolFee;
    }

    function setDefaultSwapFee(uint24 fee) external override onlyOwner {
        if (fee > MAX_SWAP_FEE) revert InvalidFee();
        defaultSwapFee = fee;
        emit UpdateDefaultSwapFee(fee);
    }

    function setCustomSwapFee(address pool, uint24 fee) external override onlyOwner {
        if (fee > MAX_SWAP_FEE) revert InvalidFee();
        customSwapFee[pool] = CustomSwapFee(true, fee);
        emit UpdateCustomSwapFee(pool, true, fee);
    }

    function removeCustomSwapFee(address pool) external override onlyOwner {
        delete customSwapFee[pool];
        emit UpdateCustomSwapFee(pool, false, 0);
    }
    */
}
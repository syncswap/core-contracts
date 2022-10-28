// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error NotFactory();
error InvalidFee();

contract PoolRegistry is Ownable {
    uint24 private constant MAX_FEE = 1e5; /// @dev 100%.
    uint24 private constant MAX_SWAP_FEE = 10000; /// @dev 10%.
    uint24 private constant ZERO_SWAP_FEE = type(uint24).max;

    /// @dev The vault that holds funds.
    address public immutable vault;

    /// @dev The default swap fee by pool type.
    mapping(uint16 => uint24) public defaultSwapFee; /// @dev `300` for 0.3%.

    /// @dev The custom swap fee by pool address, use `ZERO_SWAP_FEE` for zero fee.
    mapping(address => uint24) public customSwapFee;

    /// @dev The recipient of protocol fees.
    address public feeRecipient;

    /// @dev The protocol fee of swap fee by pool type.
    mapping(uint16 => uint24) public protocolFee; /// @dev `30000` for 30%.

    /// @dev Whether an address is a pool.
    mapping(address => bool) public isPool;

    /// @dev Whether an address is a factory.
    mapping(address => bool) public isFactory;

    event SetDefaultSwapFee(uint16 indexed poolType, uint24 defaultSwapFee);
    event SetCustomSwapFee(address indexed pool, uint24 customSwapFee);
    event SetProtocolFee(uint16 indexed poolType, uint24 protocolFee);
    event SetFeeRecipient(address indexed previousFeeRecipient, address indexed newFeeRecipient);
    event SetFactory(address indexed factory, bool isFactory);
    event RegisterPool(address indexed sender, address indexed pool);

    constructor(address _vault) {
        vault = _vault;
    }

    function getSwapFee(address pool) external view returns (uint24 swapFee) {
        uint24 _customSwapFee = customSwapFee[pool];

        if (_customSwapFee == 0) {
            swapFee = defaultSwapFee[IPool(pool).poolType()]; // use default instead if not set.
        } else {
            swapFee = (_customSwapFee == ZERO_SWAP_FEE ? 0 : _customSwapFee);
        }
    }

    function setDefaultSwapFee(uint16 poolType, uint24 _defaultSwapFee) external onlyOwner {
        if (_defaultSwapFee > MAX_SWAP_FEE) {
            revert InvalidFee();
        }
        defaultSwapFee[poolType] = _defaultSwapFee;
        emit SetDefaultSwapFee(poolType, _defaultSwapFee);
    }

    function setCustomSwapFee(address pool, uint24 _customSwapFee) external onlyOwner {
        if (_customSwapFee > MAX_SWAP_FEE && _customSwapFee != ZERO_SWAP_FEE) {
            revert InvalidFee();
        }
        customSwapFee[pool] = _customSwapFee;
        emit SetCustomSwapFee(pool, _customSwapFee);
    }

    function setProtocolFee(uint16 poolType, uint24 _protocolFee) external onlyOwner {
        if (_protocolFee > MAX_FEE) {
            revert InvalidFee();
        }
        protocolFee[poolType] = _protocolFee;
        emit SetProtocolFee(pool, _protocolFee);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setFactory(address factory, bool _isFactory) external onlyOwner {
        isFactory[factory] = _isFactory;
        emit SetFactory(factory, _isFactory);
    }

    modifier onlyFactory() {
        if (!isFactory[msg.sender]) {
            revert NotFactory();
        }
        _;
    }

    function registerPool(address pool) external onlyFactory {
        isPool[pool] = true;
        emit RegisterPool(msg.sender, pool);
    }
}
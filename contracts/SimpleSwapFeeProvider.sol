// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/ISyncSwapFactory.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/ISyncSwapPool.sol";
import "./interfaces/ISwapFeeProvider.sol";
import "./libraries/Ownable.sol";
import "./SyncSwapPool.sol";

contract SimpleSwapFeeProvider is ISwapFeeProvider, Ownable {

    uint24 private constant MAXIMUM_SWAP_FEE = 30000; // 3%

    address public factory;

    uint24 public defaultSwapFeeVolatile = 3000; // 0.3%
    uint24 public defaultSwapFeeStable = 1000; // 0.1%

    struct CustomSwapFee {
        bool exists;
        uint24 swapFee;
    }
    mapping(address => CustomSwapFee) public customSwapFeeByPool;

    event UpdateDefaultSwapFeeVolatile(uint24 swapFee);
    event UpdateDefaultSwapFeeStable(uint24 swapFee);
    event UpdateCustomSwapFee(address pool, bool exists, uint24 swapFee);

    constructor(address _factory) {
        require(_factory != address(0), "Invalid address");
        factory = _factory;
    }

    function setFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "Invalid address");
        factory = _factory;
    }

    function setDefaultSwapFeeVolatile(uint24 swapFee) external onlyOwner {
        require(swapFee <= MAXIMUM_SWAP_FEE, "Invalid swap fee");
        defaultSwapFeeVolatile = swapFee;
        emit UpdateDefaultSwapFeeVolatile(swapFee);
    }

    function setDefaultSwapFeeStable(uint24 swapFee) external onlyOwner {
        require(swapFee <= MAXIMUM_SWAP_FEE, "Invalid swap fee");
        defaultSwapFeeStable = swapFee;
        emit UpdateDefaultSwapFeeStable(swapFee);
    }

    function setCustomSwapFeeForPool(address pool, uint24 swapFee) external onlyOwner {
        require(swapFee <= MAXIMUM_SWAP_FEE, "Invalid swap fee");
        customSwapFeeByPool[pool] = CustomSwapFee(true, swapFee);
        emit UpdateCustomSwapFee(pool, true, swapFee);
    }

    function removeCustomSwapFeeForPool(address pool) external onlyOwner {
        delete customSwapFeeByPool[pool];
        emit UpdateCustomSwapFee(pool, false, 0);
    }

    function getSwapFee(
        address pool,
        address,
        address,
        uint,
        uint
    ) public override view returns (uint24 poolSwapFee) {
        // Get pool's swap fee.
        CustomSwapFee memory customSwapFee = customSwapFeeByPool[pool];
        if (customSwapFee.exists) {
            poolSwapFee = customSwapFee.swapFee;
        } else {
            poolSwapFee = ISyncSwapPool(pool).stable() ? defaultSwapFeeStable : defaultSwapFeeVolatile;
        }
    }

    function notifySwapFee(
        address pool,
        address sender,
        address from,
        uint amount0In,
        uint amount1In
    ) external override returns (uint24 poolSwapFee) {
        //require(ISyncSwapFactory(factory).isPair(pool)); // Not needed as readonly in current implementation
        poolSwapFee = getSwapFee(
            pool,
            sender,
            from,
            amount0In,
            amount1In
        );
    }
}
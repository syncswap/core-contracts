// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import './libraries/Lock.sol';
import './libraries/Math.sol';
import './interfaces/IPool.sol';
import './interfaces/IPoolFactory.sol';

library PoolContext {
    function calculateProtocolFee(uint kLast, uint reserve0, uint reserve1, address factory, uint totalSupply) external view returns (uint) {
        uint rootK = Math.sqrt(reserve0 * reserve1);
        uint rootKLast = Math.sqrt(kLast);

        if (rootK > rootKLast) {
            uint8 protocolFee = IPoolFactory(factory).protocolFee();
            uint numerator = totalSupply * (rootK - rootKLast);
            uint denominator = rootK * (protocolFee - 1) + rootKLast;
            return numerator / denominator;
        } else {
            return 0;
        }
    }
}
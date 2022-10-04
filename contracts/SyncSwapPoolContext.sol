// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./libraries/Lock.sol";
import "./libraries/Math.sol";
import "./interfaces/ISyncSwapPool.sol";
import "./interfaces/ISyncSwapFactory.sol";

library SyncSwapPoolContext {
    function calculateProtocolFee(
        uint kLast,
        uint reserve0,
        uint reserve1,
        address factory,
        uint totalSupply
    ) external view returns (uint) {
        uint rootK = Math.sqrt(reserve0 * reserve1);
        uint rootKLast = Math.sqrt(kLast);

        if (rootK > rootKLast) {
            uint8 protocolFee = ISyncSwapFactory(factory).protocolFee();
            uint numerator = totalSupply * (rootK - rootKLast);
            uint denominator = rootK * (protocolFee - 1) + rootKLast;
            return numerator / denominator;
        } else {
            return 0;
        }
    }
}
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface ISyncSwapRouter {

    struct SwapStep {
        address pool;
        bytes data;
    }

    struct SwapPath {
        SwapStep[] steps;
        address tokenIn;
        uint amountIn;
    }

    struct SplitPermitParams {
        address token;
        uint approveAmount;
        uint deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct ArrayPermitParams {
        uint approveAmount;
        uint deadline;
        bytes signature;
    }
}
// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

library SwapMath {

    function _f(uint x0, uint y) internal pure returns (uint) {
        return x0 * (y * y / 1e18 * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18) * y / 1e18;
    }

    function _d(uint x0, uint y) internal pure returns (uint) {
        return 3 * x0 * (y * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18);
    }

    function _get_y(uint x0, uint xy, uint y) internal pure returns (uint) {
        for (uint i; i < 255;) {
            uint y_prev = y;
            uint k = _f(x0, y);
            if (k < xy) {
                uint dy = (xy - k) * 1e18 / _d(x0, y);
                y = y + dy;
            } else {
                uint dy = (k - xy) * 1e18 / _d(x0, y);
                y = y - dy;
            }
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
            unchecked {
                ++i;
            }
        }
        return y;
    }

    function stableK(uint x, uint y, uint decimalsX, uint decimalsY) internal pure returns (uint) {
        uint _x = x * 1e18 / decimalsX;
        uint _y = y * 1e18 / decimalsY;
        uint _a = (_x * _y) / 1e18;
        uint _b = (_x * _x) / 1e18 + (_y * _y) / 1e18;
        return _a * _b / 1e18;
    }

    function getAmountOut(
        bool stable,
        uint fee,
        uint amountIn,
        bool isToken0,
        uint reserve0,
        uint reserve1,
        uint decimals0,
        uint decimals1
    ) internal pure returns (uint) {
        amountIn = amountIn - (amountIn * fee / 1e6);

        if (stable) {
            uint xy = stableK(reserve0, reserve1, decimals0, decimals1);
            reserve0 = reserve0 * 1e18 / decimals0;
            reserve1 = reserve1 * 1e18 / decimals1;

            (uint reserveA, uint reserveB) = isToken0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountIn = isToken0 ? amountIn * 1e18 / decimals0 : amountIn * 1e18 / decimals1;

            uint y = reserveB - _get_y(amountIn + reserveA, xy, reserveB);
            return y * (isToken0 ? decimals1 : decimals0) / 1e18;
        } else {
            (uint reserveA, uint reserveB) = isToken0 ? (reserve0, reserve1) : (reserve1, reserve0);
            return amountIn * reserveB / (reserveA + amountIn);
        }
    }
}
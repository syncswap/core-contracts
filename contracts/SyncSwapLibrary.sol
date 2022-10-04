// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/ISyncSwapPool.sol";
import "./interfaces/ISyncSwapFactory.sol";

library SyncSwapLibrary {

    struct Route {
        address fromToken;
        address toToken;
        bool stable;
    }
    
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function pairFor(address factory, address tokenA, address tokenB, bool stable) internal view returns (address) {
        return ISyncSwapFactory(factory).getPair(tokenA, tokenB, stable);
    }

    function getSwapFee(
        address factory,
        address tokenA,
        address tokenB,
        bool stable,
        address sender,
        address from,
        uint amountInA
    ) internal view returns (uint) {
        return ISyncSwapFactory(factory).getSwapFee(
            pairFor(factory, tokenA, tokenB, stable),
            sender,
            from,
            tokenA < tokenB ? amountInA : 0,
            tokenA < tokenB ? 0 : amountInA
        );
    }

    function getSwapFeeWithPool(
        address factory,
        address pool,
        address sender,
        address from,
        bool isFirstToken,
        uint amountIn
    ) internal view returns (uint24) {
        return ISyncSwapFactory(factory).getSwapFee(
            pool,
            sender,
            from,
            isFirstToken ? amountIn : 0,
            isFirstToken ? 0 : amountIn
        );
    }

    function getReserves(
        address factory,
        address tokenA,
        address tokenB,
        bool stable
    ) internal view returns (uint reserveA, uint reserveB) {
        ISyncSwapPool pool = ISyncSwapPool(pairFor(factory, tokenA, tokenB, stable));
        (uint reserve0, uint reserve1) = (pool.reserve0(), pool.reserve1());
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getReservesWithPool(
        address pool,
        address tokenA,
        address tokenB
    ) internal view returns (uint reserveA, uint reserveB) {
        (uint reserve0, uint reserve1) = (ISyncSwapPool(pool).reserve0(), ISyncSwapPool(pool).reserve1());
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getK(uint x, uint y, uint decimalsX, uint decimalsY, bool stable) internal pure returns (uint) {
        return stable ? getKStable(x, y, decimalsX, decimalsY) : getKClassic(x, y);
    }

    function getKStable(uint x, uint y, uint decimalsX, uint decimalsY) internal pure returns (uint) {
        uint _x = x * 1e18 / decimalsX;
        uint _y = y * 1e18 / decimalsY;
        uint _a = (_x * _y) / 1e18;
        uint _b = (_x * _x) / 1e18 + (_y * _y) / 1e18;
        return _a * _b / 1e18;
    }

    function getKClassic(uint x, uint y) internal pure returns (uint) {
        return x * y;
    }

    function getAmountOut(
        address factory,
        address sender,
        address from,
        uint amountIn,
        address tokenIn,
        address tokenOut,
        bool stable
    ) internal view returns (uint amountOut) {
        address pool = pairFor(factory, tokenIn, tokenOut, stable);
        amountOut = getAmountOutWithPool(
            factory,
            pool,
            sender,
            from,
            stable,
            tokenIn < tokenOut,
            amountIn
        );
    }

    function getAmountsOut(
        address factory,
        address sender,
        address from,
        uint amountIn,
        Route[] memory routes
    ) internal view returns (uint[] memory amounts) {
        //require(routes.length >= 1, "P"); // INVALID_PATH

        amounts = new uint[](routes.length + 1);
        amounts[0] = amountIn;

        uint _routesLength = routes.length;
        for (uint i; i < _routesLength;) {
            Route memory route = routes[i];
            address pool = pairFor(factory, route.fromToken, route.toToken, route.stable);

            amounts[i + 1] = getAmountOutWithPool(
                factory,
                pool,
                sender,
                from,
                route.stable,
                route.fromToken < route.toToken,
                amounts[i]
            );

            unchecked {
                ++i;
            }
        }
    }

    function getAmountOutWithPool(
        address factory,
        address pool,
        address sender,
        address from,
        bool stable,
        bool isFirstToken,
        uint amountIn
    ) internal view returns (uint) {
        uint24 swapFee = getSwapFeeWithPool(
            factory,
            pool,
            sender,
            from,
            isFirstToken,
            amountIn
        );

        return getAmountOutWithParams(
            stable,
            swapFee,
            isFirstToken,
            amountIn,
            ISyncSwapPool(pool).reserve0(),
            ISyncSwapPool(pool).reserve1(),
            ISyncSwapPool(pool).decimals0(),
            ISyncSwapPool(pool).decimals1()
        );
    }

    function getAmountOutWithParams(
        bool stable,
        uint24 swapFee,
        bool isFirstToken,
        uint amountIn,
        uint reserve0,
        uint reserve1,
        uint decimals0,
        uint decimals1
    ) internal pure returns (uint) {
        amountIn = amountIn - (amountIn * swapFee / 1e6); // subtract swap fees

        if (stable) {
            uint xy = getKStable(reserve0, reserve1, decimals0, decimals1);
            reserve0 = reserve0 * 1e18 / decimals0;
            reserve1 = reserve1 * 1e18 / decimals1;

            (uint reserveA, uint reserveB) = isFirstToken ? (reserve0, reserve1) : (reserve1, reserve0);
            amountIn = isFirstToken ? amountIn * 1e18 / decimals0 : amountIn * 1e18 / decimals1;

            uint y = reserveB - getY(amountIn + reserveA, xy, reserveB);
            return y * (isFirstToken ? decimals1 : decimals0) / 1e18;
        } else {
            (uint reserveA, uint reserveB) = isFirstToken ? (reserve0, reserve1) : (reserve1, reserve0);
            return amountIn * reserveB / (reserveA + amountIn);
        }
    }

    // Math functions
    function getF(uint x0, uint y) internal pure returns (uint) {
        return x0 * (y * y / 1e18 * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18) * y / 1e18;
    }

    function getD(uint x0, uint y) internal pure returns (uint) {
        return 3 * x0 * (y * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18);
    }

    function getY(uint x0, uint xy, uint y) internal pure returns (uint) {
        for (uint i; i < 255;) {
            uint yPrev = y;
            uint k = getF(x0, y);
            if (k < xy) {
                uint dy = (xy - k) * 1e18 / getD(x0, y);
                y = y + dy;
            } else {
                uint dy = (k - xy) * 1e18 / getD(x0, y);
                y = y - dy;
            }
            if (y > yPrev) {
                if (y - yPrev <= 1) {
                    return y;
                }
            } else {
                if (yPrev - y <= 1) {
                    return y;
                }
            }
            unchecked {
                ++i;
            }
        }
        return y;
    }
}
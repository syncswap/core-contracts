// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IWETH.sol";
import "./interfaces/IERC20Permit.sol";
import "./libraries/TransferHelper.sol";
import "./SyncSwapLibrary.sol";

contract SyncSwapRouter {

    address public immutable factory;
    // solhint-disable-next-line var-name-mixedcase
    address public immutable WETH;

    modifier ensure(uint deadline) {
        // solhint-disable-next-line not-rely-on-time
        require(deadline >= block.timestamp, "X"); // EXPIRED
        _;
    }

    // solhint-disable-next-line var-name-mixedcase
    constructor(address _factory, address _WETH) {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // TODO rescue

    function _getReserves(
        address pair,
        address tokenA,
        address tokenB
    ) private view returns (uint reserveA, uint reserveB) {
        (uint reserve0, uint reserve1) = (ISyncSwapPool(pair).reserve0(), ISyncSwapPool(pair).reserve1());
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function _quote(uint amountA, uint reserveA, uint reserveB) private pure returns (uint amountB) {
        amountB = amountA * reserveB / reserveA;
    }

    function _pairFor(address tokenA, address tokenB, bool stable) private view returns (address pair) {
        pair = ISyncSwapFactory(factory).getPair(tokenA, tokenB, stable);
    }

    function _addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal returns (address pair, uint amountA, uint amountB) {
        pair = _pairFor(tokenA, tokenB, stable);
        // create the pair if it doesn"t exist yet
        if (pair == address(0)) {
            pair = ISyncSwapFactory(factory).createPair(tokenA, tokenB, stable);
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            (uint reserveA, uint reserveB) = _getReserves(pair, tokenA, tokenB);
            if (reserveA == 0 && reserveB == 0) {
                (amountA, amountB) = (amountADesired, amountBDesired);
            } else {
                uint amountBOptimal = _quote(amountADesired, reserveA, reserveB);

                if (amountBOptimal <= amountBDesired) {
                    require(amountBOptimal >= amountBMin, "B"); // INSUFFICIENT_B_AMOUNT
                    (amountA, amountB) = (amountADesired, amountBOptimal);
                } else {
                    uint amountAOptimal = _quote(amountBDesired, reserveB, reserveA);
                    //assert(amountAOptimal <= amountADesired);
                    require(amountAOptimal >= amountAMin, "A"); // INSUFFICIENT_A_AMOUNT
                    (amountA, amountB) = (amountAOptimal, amountBDesired);
                }
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        address pair;
        (pair, amountA, amountB) = _addLiquidity(
            tokenA, tokenB, stable, amountADesired, amountBDesired, amountAMin, amountBMin
        );

        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);

        liquidity = ISyncSwapPool(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        bool stable,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        address pair;
        (pair, amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            stable,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);

        IWETH(WETH).deposit{value: amountETH}();
        // solhint-disable-next-line reason-string
        require(IWETH(WETH).transfer(pair, amountETH));
        
        liquidity = ISyncSwapPool(pair).mint(to);

        // refund dust eth, if any
        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    function _removeLiquidity(
        address pair,
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to
    ) internal returns (uint amountA, uint amountB) {
        ISyncSwapPool(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ISyncSwapPool(pair).burn(to);

        (amountA, amountB) = tokenA < tokenB ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "A"); // INSUFFICIENT_A_AMOUNT
        require(amountB >= amountBMin, "B"); // INSUFFICIENT_B_AMOUNT
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = _pairFor(tokenA, tokenB, stable);
        (amountA, amountB) = _removeLiquidity(pair, tokenA, tokenB, liquidity, amountAMin, amountBMin, to);
    }

    function _removeLiquidityETH(
        address pair,
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to
    ) internal returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = _removeLiquidity(
            pair,
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this) // send tokens to router for unwrapping
        );

        TransferHelper.safeTransfer(token, to, amountToken);

        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityETH(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint amountToken, uint amountETH) {
        address pair = _pairFor(token, WETH, stable);
        (amountToken, amountETH) = _removeLiquidityETH(pair, token, liquidity, amountTokenMin, amountETHMin, to);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, bytes calldata signature
    ) external returns (uint amountA, uint amountB) {
        address pair = _pairFor(tokenA, tokenB, stable);

        { // scope to avoid stack too deep errors
        uint value = approveMax ? type(uint).max : liquidity;
        ISyncSwapPool(pair).permit2(msg.sender, address(this), value, deadline, signature);
        }

        (amountA, amountB) = _removeLiquidity(pair, tokenA, tokenB, liquidity, amountAMin, amountBMin, to);
    }

    function removeLiquidityETHWithPermit(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, bytes calldata signature
    ) external returns (uint amountToken, uint amountETH) {
        address pair = _pairFor(token, WETH, stable);

        { // scope to avoid stack too deep errors
        uint value = approveMax ? type(uint).max : liquidity;
        ISyncSwapPool(pair).permit2(msg.sender, address(this), value, deadline, signature);
        }

        (amountToken, amountETH) = _removeLiquidityETH(pair, token, liquidity, amountTokenMin, amountETHMin, to);
    }

    function _swap(
        address pair,
        uint[] memory amounts,
        SyncSwapLibrary.Route[] memory routes,
        address to
    ) internal {
        uint _routesLength = routes.length;

        for (uint i; i < _routesLength;) {
            SyncSwapLibrary.Route memory route = routes[i];
            (uint amount0Out, uint amount1Out) = (
                route.fromToken < route.toToken ? (uint(0), amounts[i + 1]) : (amounts[i + 1], uint(0))
            );

            if (i < _routesLength - 1) {
                address _currentPair = pair;
                SyncSwapLibrary.Route memory nextRoute = routes[i + 1];
                pair = _pairFor(nextRoute.fromToken, nextRoute.toToken, nextRoute.stable); // next pair
                ISyncSwapPool(_currentPair).swap(amount0Out, amount1Out, pair, msg.sender, new bytes(0));
            } else {
                ISyncSwapPool(pair).swap(amount0Out, amount1Out, to, msg.sender, new bytes(0));
            }

            unchecked {
                ++i;
            }
        }
    }

    function _transferAndSwap(
        uint amountIn,
        uint[] memory amounts,
        SyncSwapLibrary.Route[] calldata routes,
        address to
    ) internal {
        SyncSwapLibrary.Route memory routeIn = routes[0];
        address initialPair = _pairFor(routeIn.fromToken, routeIn.toToken, routeIn.stable);
        TransferHelper.safeTransferFrom(
            routeIn.fromToken, msg.sender, initialPair, amountIn
        );
        _swap(initialPair, amounts, routes, to);
    }

    function _getAmountsOut(
        uint amountIn,
        uint amountOutMin,
        SyncSwapLibrary.Route[] calldata routes
    ) private view returns (uint[] memory amounts) {
        amounts = SyncSwapLibrary.getAmountsOut(factory, address(this), msg.sender, amountIn, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, "O"); // INSUFFICIENT_OUTPUT_AMOUNT
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        SyncSwapLibrary.Route[] calldata routes,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = _getAmountsOut(amountIn, amountOutMin, routes);
        _transferAndSwap(amountIn, amounts, routes, to);
    }

    function _permit(
        address token,
        uint amountIn,
        uint deadline,
        bool approveMax,
        uint8 v, bytes32 r, bytes32 s
    ) private {
        uint value = approveMax ? type(uint).max : amountIn;
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function swapExactTokensForTokensWithPermit(
        uint amountIn,
        uint amountOutMin,
        SyncSwapLibrary.Route[] calldata routes,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = _getAmountsOut(amountIn, amountOutMin, routes);

        // Approve tokens with permit.
        _permit(routes[0].fromToken, amountIn, deadline, approveMax, v, r, s);

        _transferAndSwap(amountIn, amounts, routes, to);
    }

    function swapExactETHForTokens(
        uint amountOutMin,
        SyncSwapLibrary.Route[] calldata routes,
        address to,
        uint deadline
    ) external payable ensure(deadline) returns (uint[] memory amounts) {
        amounts = _getAmountsOut(msg.value, amountOutMin, routes);

        uint amountIn = amounts[0];
        IWETH(WETH).deposit{value: amountIn}();

        SyncSwapLibrary.Route memory routeIn = routes[0];
        address initialPair = _pairFor(routeIn.fromToken, routeIn.toToken, routeIn.stable);
        // solhint-disable-next-line reason-string
        require(IWETH(WETH).transfer(initialPair, amountIn));

        _swap(initialPair, amounts, routes, to);
    }

    function _transferAndSwapETH(
        uint amountIn,
        uint amountOut,
        uint[] memory amounts,
        SyncSwapLibrary.Route[] calldata routes,
        address to
    ) internal {
        _transferAndSwap(amountIn, amounts, routes, address(this)); // send tokens to router for unwrapping

        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        SyncSwapLibrary.Route[] calldata routes,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = _getAmountsOut(amountIn, amountOutMin, routes);

        _transferAndSwapETH(amountIn, amounts[amounts.length - 1], amounts, routes, to);
    }

    function swapExactTokensForETHWithPermit(
        uint amountIn,
        uint amountOutMin,
        SyncSwapLibrary.Route[] calldata routes,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external ensure(deadline) returns (uint[] memory amounts) {
        amounts = _getAmountsOut(amountIn, amountOutMin, routes);

        // Approve tokens with permit.
        _permit(routes[0].fromToken, amountIn, deadline, approveMax, v, r, s);

        _transferAndSwapETH(amountIn, amounts[amounts.length - 1], amounts, routes, to);
    }

    /*
    function _swapSupportingFeeOnTransferTokens(
        address pair,
        SyncSwapLibrary.Route[] memory routes,
        address to
    ) internal {
        uint _routesLength = routes.length;

        for (uint i; i < _routesLength;) {
            SyncSwapLibrary.Route memory route = routes[i];

            uint amountOut;
            {
            (uint reserve0, uint reserve1) = (ISyncSwapPool(pair).reserve0(), ISyncSwapPool(pair).reserve1());
            (uint reserveIn, uint reserveOut) = (
                route.fromToken < route.toToken ? (reserve0, reserve1) : (reserve1, reserve0)
            );
            uint amountIn = IERC20(route.fromToken).balanceOf(pair) - reserveIn;
            amountOut = getAmountOut(
                amountIn,
                reserveIn,
                reserveOut,
                ISyncSwapFactory(factory).swapFee(pair)
            ); // TODO
            }
            (uint amount0Out, uint amount1Out) = (
                route.fromToken < route.toToken ? (0, amounts[i + 1]) : (amounts[i + 1], 0)
            );

            if (i < _routesLength - 1) {
                address _currentPair = pair;
                SyncSwapLibrary.Route memory nextRoute = routes[i + 1];
                pair = _pairFor(nextRoute.fromToken, nextRoute.toToken, nextRoute.stable); // next pair
                ISyncSwapPool(_currentPair).swap(amount0Out, amount1Out, pair, msg.sender, new bytes(0));
            } else {
                ISyncSwapPool(pair).swap(amount0Out, amount1Out, to, msg.sender, new bytes(0));
            }

            unchecked {
                ++i;
            }
        }
    }
    */
}
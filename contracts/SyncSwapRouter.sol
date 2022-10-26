// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IWETH.sol";
import "./interfaces/IERC20Permit.sol";
import "./interfaces/IPool.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IBasePool.sol";
import "./interfaces/ISyncSwapRouter.sol";
import "./interfaces/ISyncSwapFactory.sol";
import "./libraries/TransferHelper.sol";

error NotEnoughLiquidityMinted();
error TooLittleReceived();
error Expired();

contract SyncSwapRouter is ISyncSwapRouter {

    address public immutable vault;
    address public immutable factory;
    address public immutable wETH;
    address private constant NATIVE_ETH = address(0);

    modifier ensure(uint deadline) {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    constructor(address _vault, address _factory, address _wETH) {
        vault = _vault;
        factory = _factory;
        wETH = _wETH;
    }

    receive() external payable {
        assert(msg.sender == wETH); // only accept ETH via fallback from the WETH contract
    }

    /*
    function _getPool(address tokenA, address tokenB, bool stable) private view returns (address pool) {
        pool = ISyncSwapFactory(factory).getPool(tokenA, tokenB, stable);
    }

    function _getOrCreatePool(address tokenA, address tokenB, bool stable) private returns (address pool) {
        pool = ISyncSwapFactory(factory).getPool(tokenA, tokenB, stable);

        // Creates the pool if not exists.
        if (pool == address(0)) {
            pool = ISyncSwapFactory(factory).createPool(tokenA, tokenB, stable);
        }
    }
    */

    // Add Liquidity
    /*
    function _transferAndAddLiquidity(
        address pool,
        address tokenA,
        address tokenB,
        uint amountA,
        uint amountB,
        uint minLiquidity,
        address to,
        bool ethIn
    ) private returns (uint liquidity) {
        if (ethIn) {
            _transferTokensOrETHFromSender(tokenA, pool, amountA);
            _transferTokensOrETHFromSender(tokenB, pool, amountB);
        } else {
            TransferHelper.safeTransferFrom(tokenA, msg.sender, pool, amountA);
            TransferHelper.safeTransferFrom(tokenB, msg.sender, pool, amountB);
        }

        liquidity = ISyncSwapPool(pool).mint(to);
        if (liquidity < minLiquidity) {
            revert NotEnoughLiquidityMinted();
        }
    }
    */

    struct TokenInput {
        address token;
        uint amount;
    }

    function _transferFromSender(address token, address to, uint amount) private {
        if (token == NATIVE_ETH) {
            // Wrap native ETH to wETH.
            //IWETH(wETH).deposit{value: msg.value}();

            // Send wETH to recipient.
            //require(IWETH(wETH).transfer(to, amount));
            IVault(vault).deposit{value: msg.value}(token, to);
        } else {
            // Transfer tokens to the vault.
            TransferHelper.safeTransferFrom(token, msg.sender, vault, amount);

            // Notify the vault to deposit.
            IVault(vault).deposit(token, to);
        }
    }

    function _transferAndAddLiquidity(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity
    ) private returns (uint liquidity) {
        // Send all input tokens to the pool.
        uint n = inputs.length;

        TokenInput memory input;

        for (uint i; i < n; ) {
            input = inputs[i];

            _transferFromSender(input.token, pool, input.amount);

            unchecked {
                ++i;
            }
        }

        liquidity = IPool(pool).mint(data);

        if (liquidity < minLiquidity) {
            revert NotEnoughLiquidityMinted();
        }
    }

    function addLiquidity(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity
    ) external payable returns (uint liquidity) {
        liquidity = _transferAndAddLiquidity(
            pool,
            inputs,
            data,
            minLiquidity
        );
    }

    function addLiquidityWithPermit(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        SplitPermitParams[] memory permits
    ) external payable returns (uint liquidity) {
        // Approve all tokens via permit.
        uint n = permits.length;

        SplitPermitParams memory params;

        for (uint i; i < n; ) {
            params = permits[i];

            IERC20Permit(params.token).permit(
                msg.sender,
                address(this),
                params.approveAmount,
                params.deadline,
                params.v,
                params.r,
                params.s
            );

            unchecked {
                ++i;
            }
        }

        liquidity = _transferAndAddLiquidity(
            pool,
            inputs,
            data,
            minLiquidity
        );
    }

    /*
    function addLiquidityWithPermit(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountA,
        uint amountB,
        uint minLiquidity,
        address to,
        bool ethIn,
        SplitPermitParams[] memory permitParams
    ) external payable returns (uint liquidity, address pool) {
        pool = _getOrCreatePool(tokenA, tokenB, stable);

        if (permitParams.length != 0) {
            // Approve `tokenA` via permit.
            SplitPermitParams memory data = permitParams[0];
            IERC20Permit(tokenA).permit(
                msg.sender,
                address(this),
                data.approveAmount,
                data.deadline,
                data.v,
                data.r,
                data.s
            );

            if (permitParams.length == 2) {
                // Approve `tokenB` via permit.
                data = permitParams[1];
                IERC20Permit(tokenB).permit(
                    msg.sender,
                    address(this),
                    data.approveAmount,
                    data.deadline,
                    data.v,
                    data.r,
                    data.s
                );
            }
        }

        liquidity = _transferAndAddLiquidity(
            pool,
            tokenA,
            tokenB,
            amountA,
            amountB,
            minLiquidity,
            to,
            ethIn
        );
    }
    */

    // Remove Liquidity
    function _transferAndBurnLiquidity(
        address pool,
        uint liquidity,
        bytes memory data,
        uint[] memory minAmounts
        /*
        address tokenA,
        address tokenB,
        uint liquidity,
        uint minAmountA,
        uint minAmountB,
        address to,
        bool ethOut
        */
    ) private returns (IPool.TokenAmount[] memory amounts) {
        IBasePool(pool).transferFrom(msg.sender, pool, liquidity);

        amounts = IPool(pool).burn(data);

        uint n = amounts.length;

        for (uint i; i < n; ) {
            if (amounts[i].amount < minAmounts[i]) {
                revert TooLittleReceived();
            }

            unchecked {
                ++i;
            }
        }
    }

    function burnLiquidity(
        address pool,
        uint liquidity,
        bytes calldata data,
        uint[] calldata minAmounts
    ) external returns (IPool.TokenAmount[] memory amounts) {
        amounts = _transferAndBurnLiquidity(
            pool,
            liquidity,
            data,
            minAmounts
        );
    }

    function burnLiquidityWithPermit(
        address pool,
        uint liquidity,
        bytes calldata data,
        uint[] calldata minAmounts,
        ArrayPermitParams memory permit
    ) external returns (IPool.TokenAmount[] memory amounts) {
        // Approve liquidity via permit.
        IBasePool(pool).permit2(
            msg.sender,
            address(this),
            permit.approveAmount,
            permit.deadline,
            permit.signature
        );

        amounts = _transferAndBurnLiquidity(
            pool,
            liquidity,
            data,
            minAmounts
        );
    }

    // Remove Liquidity Single
    function _transferAndBurnLiquiditySingle(
        address pool,
        uint liquidity,
        bytes memory data,
        uint minAmount
    ) private returns (uint amountOut) {
        IBasePool(pool).transferFrom(msg.sender, pool, liquidity);

        amountOut = IPool(pool).burnSingle(data);

        if (amountOut < minAmount) {
            revert TooLittleReceived();
        }
    }

    function burnLiquiditySingle(
        address pool,
        uint liquidity,
        bytes memory data,
        uint minAmount
    ) external returns (uint amountOut) {
        amountOut = _transferAndBurnLiquiditySingle(
            pool,
            liquidity,
            data,
            minAmount
        );
    }

    function removeLiquiditySingleWithPermit(
        address pool,
        uint liquidity,
        bytes memory data,
        uint minAmount,
        ArrayPermitParams calldata permit
    ) external returns (uint amountOut) {
        // Approve liquidity via permit.
        IBasePool(pool).permit2(
            msg.sender,
            address(this),
            permit.approveAmount,
            permit.deadline,
            permit.signature
        );

        amountOut = _transferAndBurnLiquiditySingle(
            pool,
            liquidity,
            data,
            minAmount
        );
    }

    /*
    function swapExactInputSingle(
        address fromToken,
        address toToken,
        bool stable,
        uint amountIn,
        uint amountOutMin,
        address to,
        bool ethIn,
        bool ethOut
    ) external returns (uint amountOut) {
        // Prefund the pool.
        address pool = _getPool(fromToken, toToken, stable);
        if (ethIn) {
            _transferETHFromSender(pool, amountIn);
        } else {
            TransferHelper.safeTransferFrom(fromToken, msg.sender, pool, amountIn);
        }

        // Perform the swap.
        amountOut = ISyncSwapPool(pool).swap(
            toToken,
            ethOut ? address(this) : to
        );

        // Ensure the slippage.
        if (amountOut < amountOutMin) {
            revert TooLittleReceived();
        }

        // Unwrap and send native ETH if required.
        if (ethOut) {
            _sendEtherTo(to, amountOut);
        }
    }
    */

    function _swapExactInput(
        SwapPath[] memory paths,
        uint amountOutMin
    ) private returns (uint amountOut) {
        uint pathsLength = paths.length;

        SwapPath memory path;
        SwapStep memory step;
        uint stepsLength;
        uint j;

        for (uint i; i < pathsLength; ) {
            path = paths[i];

            // Prefund the first step.
            step = path.steps[0];
            _transferFromSender(path.tokenIn, step.pool, path.amountIn);

            // Cache steps length.
            stepsLength = path.steps.length;

            for (j; j < stepsLength; ) {
                if (j < stepsLength - 1) {
                    // Swap and send tokens to the next step.
                    IBasePool(step.pool).swap(step.data);

                    // Cache the next step.
                    step = path.steps[j + 1];
                } else {
                    // Accumulate output amount at the last step.
                    amountOut += IBasePool(step.pool).swap(step.data);
                }

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }

        if (amountOut < amountOutMin) {
            revert TooLittleReceived();
        }
    }

    /*
    function _swapExactInput(
        address pool,
        uint amountIn,
        uint amountOutMin,
        SwapPath[] memory path,
        address to,
        bool ethIn,
        bool ethOut
    ) private returns (uint amountOut) {
        // Cache and prefund the first pool.
        //SwapPath memory pathIn = path[0];
        //address pool = _getPool(pathIn.fromToken, pathIn.toToken, pathIn.stable);
        if (ethIn) {
            _transferETHFromSender(pool, amountIn);
        } else {
            TransferHelper.safeTransferFrom(path[0].fromToken, msg.sender, pool, amountIn);
        }

        uint pathLength = path.length;
        for (uint i; i < pathLength; ) {
            SwapPath memory currentPath = path[i];

            if (i < pathLength - 1) {
                // Cache the next pool.
                address currentPool = pool;
                SwapPath memory nextPath = path[i + 1];
                pool = _getPool(nextPath.fromToken, nextPath.toToken, nextPath.stable); // next pool

                // Perform the swap, and send output tokens to the next pool.
                ISyncSwapPool(currentPool).swap(currentPath.fromToken, pool);

                unchecked {
                    ++i;
                }
            } else {
                // Perform the swap.
                amountOut = ISyncSwapPool(pool).swap(
                    currentPath.toToken,
                    ethOut ? address(this) : to
                );

                // Ensure the slippage.
                if (amountOut < amountOutMin) {
                    revert TooLittleReceived();
                }

                // Unwrap and send native ETH if required.
                if (ethOut) {
                    _sendEtherTo(to, amountOut);
                }
            }
        }
    }
    */

    function swapExactInput(
        SwapPath[] memory paths,
        uint amountOutMin,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountOut) {
        amountOut = _swapExactInput(
            paths,
            amountOutMin
        );
    }

    function swapExactInputWithPermit(
        SwapPath[] memory paths,
        uint amountOutMin,
        uint deadline,
        SplitPermitParams calldata permit
    ) external payable ensure(deadline) returns (uint amountOut) {
        // Approve input tokens via permit.
        IERC20Permit(permit.token).permit(
            msg.sender,
            address(this),
            permit.approveAmount,
            permit.deadline,
            permit.v,
            permit.r,
            permit.s
        );

        amountOut = _swapExactInput(
            paths,
            amountOutMin
        );
    }

    /*
    function _transferTokensOrETHFromSender(address token, address to, uint amount) private {
        if (token == wETH) {
            _transferETHFromSender(to, amount);
        } else {
            TransferHelper.safeTransferFrom(token, msg.sender, to, amount);
        }
    }

    function _transferETHFromSender(address to, uint amount) private {
        IWETH(wETH).deposit{value: msg.value}();
        require(IWETH(wETH).transfer(to, amount));
    }
    */
}
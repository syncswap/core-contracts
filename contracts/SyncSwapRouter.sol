// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IWETH.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/pool/IPool.sol";
import "./interfaces/pool/IBasePool.sol";
import "./interfaces/token/IERC20Permit.sol";
import "./interfaces/factory/IPoolFactory.sol";

import "./libraries/TransferHelper.sol";

import "./abstract/SelfPermit.sol";
import "./abstract/Multicall.sol";

error NotEnoughLiquidityMinted();
error TooLittleReceived();
error Expired();

/// @notice The router is a universal interface for users to access
/// functions across different protocol parts in one place.
///
/// It handles the allowances and transfers of tokens, and
/// allows chained swaps/operations across multiple pools, with
/// additional features like slippage protection and permit support.
///
contract SyncSwapRouter is IRouter, SelfPermit, Multicall {

    struct TokenInput {
        address token;
        uint amount;
    }

    address public immutable vault;
    address public immutable wETH;
    address private constant NATIVE_ETH = address(0);

    modifier ensure(uint deadline) {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > deadline) {
            revert Expired();
        }
        _;
    }

    constructor(address _vault, address _wETH) {
        vault = _vault;
        wETH = _wETH;
    }

    /*
    receive() external payable {
        require(msg.sender == wETH); // only accept ETH via fallback from the WETH contract
    }
    */

    // Add Liquidity
    function _transferFromSender(address token, address to, uint amount) private {
        if (token == NATIVE_ETH) {
            // Deposit ETH to the vault.
            IVault(vault).deposit{value: amount}(token, to);
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

    // Burn Liquidity
    function _transferAndBurnLiquidity(
        address pool,
        uint liquidity,
        bytes memory data,
        uint[] memory minAmounts
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

    // Burn Liquidity Single
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

    function burnLiquiditySingleWithPermit(
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

    // Swap
    function _swap(
        SwapPath[] memory paths,
        uint amountOutMin
    ) private returns (uint amountOut) {
        uint pathsLength = paths.length;

        SwapPath memory path;
        SwapStep memory step;
        uint stepsLength;

        for (uint i; i < pathsLength; ) {
            path = paths[i];

            // Prefund the first step.
            step = path.steps[0];
            _transferFromSender(path.tokenIn, step.pool, path.amountIn);

            // Cache steps length.
            stepsLength = path.steps.length;

            for (uint j; j < stepsLength; ) {
                if (j == stepsLength - 1) {
                    // Accumulate output amount at the last step.
                    amountOut += IBasePool(step.pool).swap(step.data);
                    break;
                } else {
                    // Swap and send tokens to the next step.
                    IBasePool(step.pool).swap(step.data);

                    // Cache the next step.
                    step = path.steps[j + 1];
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

    function swap(
        SwapPath[] memory paths,
        uint amountOutMin,
        uint deadline
    ) external payable ensure(deadline) returns (uint amountOut) {
        amountOut = _swap(
            paths,
            amountOutMin
        );
    }

    function swapWithPermit(
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

        amountOut = _swap(
            paths,
            amountOutMin
        );
    }

    /// @notice Wrapper function to allow pool deployment to be batched.
    function createPool(address _factory, bytes calldata data) external payable returns (address) {
        return IPoolFactory(_factory).createPool(data);
    }

    function stake(address stakingPool, address token, uint amount, address onBehalf) external {
        TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

        if (IERC20(token).allowance(address(this), stakingPool) < amount) {
            TransferHelper.safeApprove(token, stakingPool, type(uint).max);
        }

        IStakingPool(stakingPool).stake(amount, onBehalf);
    }
}
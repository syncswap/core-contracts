// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

import "./interfaces/IWETH.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IStakingPool.sol";
import "./interfaces/vault/IVault.sol";
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

    mapping(address => mapping(address => bool)) public isPoolEntered;
    mapping(address => address[]) public enteredPools;

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

    function enteredPoolsLength(address account) external view returns (uint) {
        return enteredPools[account].length;
    }

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
        uint minLiquidity,
        address callback,
        bytes calldata callbackData
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

        liquidity = IPool(pool).mint(data, msg.sender, callback, callbackData);

        if (liquidity < minLiquidity) {
            revert NotEnoughLiquidityMinted();
        }
    }

    function _markPoolEntered(address pool) private {
        if (!isPoolEntered[pool][msg.sender]) {
            isPoolEntered[pool][msg.sender] = true;
            enteredPools[msg.sender].push(pool);
        }
    }

    function addLiquidity(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        address callback,
        bytes calldata callbackData
    ) external payable returns (uint liquidity) {
        liquidity = _transferAndAddLiquidity(
            pool,
            inputs,
            data,
            minLiquidity,
            callback,
            callbackData
        );
    }

    function addLiquidity2(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        address callback,
        bytes calldata callbackData
    ) external payable returns (uint liquidity) {
        liquidity = _transferAndAddLiquidity(
            pool,
            inputs,
            data,
            minLiquidity,
            callback,
            callbackData
        );

        _markPoolEntered(pool);
    }

    function addLiquidityWithPermit(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        address callback,
        bytes calldata callbackData,
        SplitPermitParams[] memory permits
    ) public payable returns (uint liquidity) {
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
            minLiquidity,
            callback,
            callbackData
        );
    }

    function addLiquidityWithPermit2(
        address pool,
        TokenInput[] calldata inputs,
        bytes calldata data,
        uint minLiquidity,
        address callback,
        bytes calldata callbackData,
        SplitPermitParams[] memory permits
    ) public payable returns (uint liquidity) {
        liquidity = addLiquidityWithPermit(
            pool,
            inputs,
            data,
            minLiquidity,
            callback,
            callbackData,
            permits
        );

        _markPoolEntered(pool);
    }

    // Burn Liquidity
    function _transferAndBurnLiquidity(
        address pool,
        uint liquidity,
        bytes memory data,
        uint[] memory minAmounts,
        address callback,
        bytes calldata callbackData
    ) private returns (IPool.TokenAmount[] memory amounts) {
        IBasePool(pool).transferFrom(msg.sender, pool, liquidity);

        amounts = IPool(pool).burn(data, msg.sender, callback, callbackData);

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
        uint[] calldata minAmounts,
        address callback,
        bytes calldata callbackData
    ) external returns (IPool.TokenAmount[] memory amounts) {
        amounts = _transferAndBurnLiquidity(
            pool,
            liquidity,
            data,
            minAmounts,
            callback,
            callbackData
        );
    }

    function burnLiquidityWithPermit(
        address pool,
        uint liquidity,
        bytes calldata data,
        uint[] calldata minAmounts,
        address callback,
        bytes calldata callbackData,
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
            minAmounts,
            callback,
            callbackData
        );
    }

    // Burn Liquidity Single
    function _transferAndBurnLiquiditySingle(
        address pool,
        uint liquidity,
        bytes memory data,
        uint minAmount,
        address callback,
        bytes memory callbackData
    ) private returns (IPool.TokenAmount memory amountOut) {
        IBasePool(pool).transferFrom(msg.sender, pool, liquidity);

        amountOut = IPool(pool).burnSingle(data, msg.sender, callback, callbackData);

        if (amountOut.amount < minAmount) {
            revert TooLittleReceived();
        }
    }

    function burnLiquiditySingle(
        address pool,
        uint liquidity,
        bytes memory data,
        uint minAmount,
        address callback,
        bytes memory callbackData
    ) external returns (IPool.TokenAmount memory amountOut) {
        amountOut = _transferAndBurnLiquiditySingle(
            pool,
            liquidity,
            data,
            minAmount,
            callback,
            callbackData
        );
    }

    function burnLiquiditySingleWithPermit(
        address pool,
        uint liquidity,
        bytes memory data,
        uint minAmount,
        address callback,
        bytes memory callbackData,
        ArrayPermitParams calldata permit
    ) external returns (IPool.TokenAmount memory amountOut) {
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
            minAmount,
            callback,
            callbackData
        );
    }

    // Swap
    function _swap(
        SwapPath[] memory paths,
        uint amountOutMin
    ) private returns (IPool.TokenAmount memory amountOut) {
        uint pathsLength = paths.length;

        SwapPath memory path;
        SwapStep memory step;
        IPool.TokenAmount memory tokenAmount;
        uint stepsLength;
        uint j;

        for (uint i; i < pathsLength; ) {
            path = paths[i];

            // Prefund the first step.
            step = path.steps[0];
            _transferFromSender(path.tokenIn, step.pool, path.amountIn);

            // Cache steps length.
            stepsLength = path.steps.length;

            for (j = 0; j < stepsLength; ) {
                if (j == stepsLength - 1) {
                    // Accumulate output amount at the last step.
                    tokenAmount = IBasePool(step.pool).swap(
                        step.data, msg.sender, step.callback, step.callbackData
                    );

                    amountOut.token = tokenAmount.token;
                    amountOut.amount += tokenAmount.amount;

                    break;
                } else {
                    // Swap and send tokens to the next step.
                    IBasePool(step.pool).swap(step.data, msg.sender, step.callback, step.callbackData);

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

        if (amountOut.amount < amountOutMin) {
            revert TooLittleReceived();
        }
    }

    function swap(
        SwapPath[] memory paths,
        uint amountOutMin,
        uint deadline
    ) external payable ensure(deadline) returns (IPool.TokenAmount memory amountOut) {
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
    ) external payable ensure(deadline) returns (IPool.TokenAmount memory amountOut) {
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
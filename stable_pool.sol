
// File contracts/interfaces/IFeeManager.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @dev The manager contract to control fees.
/// Management functions are omitted.
interface IFeeManager {
    function defaultSwapFee(uint16 poolType) external view returns (uint24);

    function customSwapFee(address pool) external view returns (uint24);

    function feeRecipient() external view returns (address);

    function protocolFee(uint16 poolType) external view returns (uint24);
    
    function getSwapFee(address pool) external view returns (uint24 swapFee);
}


// File contracts/interfaces/IPoolMaster.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
/// @dev The master contract to create pools and manage whitelisted factories.
/// Inheriting the fee manager interface to support fee queries.
interface IPoolMaster is IFeeManager {
    event SetFactoryWhitelisted(address indexed factory, bool whitelisted);

    event RegisterPool(
        address indexed factory,
        address indexed pool,
        uint16 indexed poolType,
        bytes data
    );

    event UpdateFeeManager(address indexed previousFeeManager, address indexed newFeeManager);

    function vault() external view returns (address);

    function feeManager() external view returns (address);

    // Fees
    function setFeeManager(address) external;

    // Factories
    function isFactoryWhitelisted(address) external view returns (bool);

    function setFactoryWhitelisted(address factory, bool whitelisted) external;

    // Pools
    function isPool(address) external view returns (bool);

    function getPool(bytes32) external view returns (address);

    function createPool(address factory, bytes calldata data) external returns (address pool);

    function registerPool(address pool, uint16 poolType, bytes calldata data) external;
}


// File contracts/interfaces/pool/IPool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPool {
    struct TokenAmount {
        address token;
        uint amount;
    }

    /// @dev Returns the address of pool master.
    function master() external view returns (address);

    /// @dev Returns the vault.
    function vault() external view returns (address);

    /// @dev Returns the pool type.
    function poolType() external view returns (uint16);

    /// @dev Returns the assets of the pool.
    function getAssets() external view returns (address[] memory assets);

    /// @dev Returns the swap fee of the pool.
    function getSwapFee() external view returns (uint24 swapFee);

    /// @dev Returns the protocol fee of the pool.
    function getProtocolFee() external view returns (uint24 protocolFee);

    /// @dev Mints liquidity.
    function mint(bytes calldata data) external returns (uint liquidity);

    /// @dev Burns liquidity.
    function burn(bytes calldata data) external returns (TokenAmount[] memory amounts);

    /// @dev Burns liquidity with single output token.
    function burnSingle(bytes calldata data) external returns (uint amountOut);

    /// @dev Swaps between tokens.
    function swap(bytes calldata data) external returns (uint amountOut);
}


// File contracts/interfaces/token/IERC20Base.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IERC20Base {
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    
    event Approval(address indexed owner, address indexed spender, uint amount);
    event Transfer(address indexed from, address indexed to, uint amount);
}


// File contracts/interfaces/token/IERC20.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IERC20 is IERC20Base {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}


// File contracts/interfaces/token/IERC20Permit.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IERC20Permit is IERC20 {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function nonces(address owner) external view returns (uint);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}


// File contracts/interfaces/token/IERC20Permit2.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IERC20Permit2 is IERC20Permit {
    function permit2(address owner, address spender, uint amount, uint deadline, bytes calldata signature) external;
}


// File contracts/interfaces/pool/IBasePool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IBasePool is IPool, IERC20Permit2 {
    function token0() external view returns (address);
    function token1() external view returns (address);

    function reserve0() external view returns (uint);
    function reserve1() external view returns (uint);
    function invariantLast() external view returns (uint);

    function getReserves() external view returns (uint, uint);
    function getAmountOut(address tokenIn, uint amountIn) external view returns (uint amountOut);
    function getAmountIn(address tokenOut, uint amountOut) external view returns (uint amountIn);

    event Mint(
        address indexed sender,
        uint amount0,
        uint amount1,
        uint liquidity,
        address indexed to
    );

    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        uint liquidity,
        address indexed to
    );

    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );

    event Sync(
        uint reserve0,
        uint reserve1
    );
}


// File contracts/interfaces/pool/IStablePool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IStablePool is IBasePool {
    function token0PrecisionMultiplier() external view returns (uint);
    function token1PrecisionMultiplier() external view returns (uint);
}


// File contracts/interfaces/vault/IFlashLoanRecipient.sol

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.7.0 <0.9.0;

// Inspired by Aave Protocol's IFlashLoanReceiver.

interface IFlashLoanRecipient {
    /**
     * @dev When `flashLoan` is called on the Vault, it invokes the `receiveFlashLoan` hook on the recipient.
     *
     * At the time of the call, the Vault will have transferred `amounts` for `tokens` to the recipient. Before this
     * call returns, the recipient must have transferred `amounts` plus `feeAmounts` for each token back to the
     * Vault, or else the entire flash loan will revert.
     *
     * `userData` is the same value passed in the `IVault.flashLoan` call.
     */
    function receiveFlashLoan(
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts,
        bytes memory userData
    ) external;
}


// File contracts/interfaces/vault/IFlashLoan.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IFlashLoan {
    /**
     * @dev Performs a 'flash loan', sending tokens to `recipient`, executing the `receiveFlashLoan` hook on it,
     * and then reverting unless the tokens plus a proportional protocol fee have been returned.
     *
     * The `tokens` and `amounts` arrays must have the same length, and each entry in these indicates the loan amount
     * for each token contract. `tokens` must be sorted in ascending order.
     *
     * The 'userData' field is ignored by the Vault, and forwarded as-is to `recipient` as part of the
     * `receiveFlashLoan` call.
     *
     * Emits `FlashLoan` events.
     */
    function flashLoan(
        IFlashLoanRecipient recipient,
        address[] memory tokens,
        uint[] memory amounts,
        bytes memory userData
    ) external;

    function flashLoanFeePercentage() external view returns (uint);

    /**
     * @dev Emitted for each individual flash loan performed by `flashLoan`.
     */
    event FlashLoan(IFlashLoanRecipient indexed recipient, address indexed token, uint amount, uint feeAmount);
}


// File contracts/interfaces/vault/IVault.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IVault is IFlashLoan {
    function wETH() external view returns (address);

    function reserves(address token) external view returns (uint reserve);

    function balanceOf(address token, address owner) external view returns (uint balance);

    function deposit(address token, address to) external payable returns (uint amount);

    function depositETH(address to) external payable returns (uint amount);

    function transferAndDeposit(address token, address to, uint amount) external payable returns (uint);

    function transfer(address token, address to, uint amount) external;

    function withdraw(address token, address to, uint amount) external;

    function withdrawAlternative(address token, address to, uint amount, uint8 mode) external;

    function withdrawETH(address to, uint amount) external;
}


// File contracts/libraries/ECDSA.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 *
 * Based on OpenZeppelin's ECDSA library.
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/561d1061fc568f04c7a65853538e834a889751e8/contracts/utils/cryptography/ECDSA.sol
 */
library ECDSA {

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature` or error string. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        // Check the signature length
        if (signature.length != 65) {
            return address(0);
        }

        // Divide the signature in r, s and v variables
        bytes32 r;
        bytes32 s;
        uint8 v;

        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        /// @solidity memory-safe-assembly
        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        return ecrecover(hash, v, r, s);
    }

    function toArraySignature(
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (bytes memory) {
        bytes memory signature = new bytes(65);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            mstore(add(signature, 32), r)
            mstore(add(signature, 64), s)
            mstore8(add(signature, 96), v)
        }

        return signature;
    }
}


// File contracts/libraries/SignatureChecker.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
/**
 * @dev Signature verification helper that can be used instead of `ECDSA.recover` to seamlessly support both ECDSA
 * signatures from externally owned accounts (EOAs) as well as ERC1271 signatures from smart contract wallets like
 * Argent and Gnosis Safe.
 *
 * Based on OpenZeppelin's SignatureChecker library.
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/561d1061fc568f04c7a65853538e834a889751e8/contracts/utils/cryptography/SignatureChecker.sol
 */
library SignatureChecker {

    bytes4 constant internal MAGICVALUE = 0x1626ba7e; // bytes4(keccak256("isValidSignature(bytes32,bytes)")

    /** 
     * @dev Checks if a signature is valid for a given signer and data hash. If the signer is a smart contract, the
     * signature is validated against that smart contract using ERC1271, otherwise it's validated using `ECDSA.recover`.
     *
     * NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function can thus
     * change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidSignatureNow(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        (address recovered) = ECDSA.recover(hash, signature);
        if (recovered != address(0) && recovered == signer) {
            return true;
        }

        (bool success, bytes memory result) = signer.staticcall(
            abi.encodeWithSelector(MAGICVALUE, hash, signature)
        );
        return (
            success &&
            result.length == 32 &&
            abi.decode(result, (bytes32)) == bytes32(MAGICVALUE)
        );
    }
}


// File contracts/libraries/Math.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

/// @dev Math functions.
/// @dev Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/utils/FixedPointMathLib.sol)
library Math {

    /// @notice Compares a and b and returns 'true' if the difference between a and b
    /// is less than 1 or equal to each other.
    /// @param a uint256 to compare with.
    /// @param b uint256 to compare with.
    function within1(uint256 a, uint256 b) internal pure returns (bool) {
        unchecked {
            if (a > b) {
                return a - b <= 1;
            }
            return b - a <= 1;
        }
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        assembly {
            let y := x // We start y at x, which will help us make our initial estimate.

            z := 181 // The "correct" value is 1, but this saves a multiplication later.

            // This segment is to get a reasonable initial estimate for the Babylonian method. With a bad
            // start, the correct # of bits increases ~linearly each iteration instead of ~quadratically.

            // We check y >= 2^(k + 8) but shift right by k bits
            // each branch to ensure that if x >= 256, then y >= 256.
            if iszero(lt(y, 0x10000000000000000000000000000000000)) {
                y := shr(128, y)
                z := shl(64, z)
            }
            if iszero(lt(y, 0x1000000000000000000)) {
                y := shr(64, y)
                z := shl(32, z)
            }
            if iszero(lt(y, 0x10000000000)) {
                y := shr(32, y)
                z := shl(16, z)
            }
            if iszero(lt(y, 0x1000000)) {
                y := shr(16, y)
                z := shl(8, z)
            }

            // Goal was to get z*z*y within a small factor of x. More iterations could
            // get y in a tighter range. Currently, we will have y in [256, 256*2^16).
            // We ensured y >= 256 so that the relative difference between y and y+1 is small.
            // That's not possible if x < 256 but we can just verify those cases exhaustively.

            // Now, z*z*y <= x < z*z*(y+1), and y <= 2^(16+8), and either y >= 256, or x < 256.
            // Correctness can be checked exhaustively for x < 256, so we assume y >= 256.
            // Then z*sqrt(y) is within sqrt(257)/sqrt(256) of sqrt(x), or about 20bps.

            // For s in the range [1/256, 256], the estimate f(s) = (181/1024) * (s+1) is in the range
            // (1/2.84 * sqrt(s), 2.84 * sqrt(s)), with largest error when s = 1 and when s = 256 or 1/256.

            // Since y is in [256, 256*2^16), let a = y/65536, so that a is in [1/256, 256). Then we can estimate
            // sqrt(y) using sqrt(65536) * 181/1024 * (a + 1) = 181/4 * (y + 65536)/65536 = 181 * (y + 65536)/2^18.

            // There is no overflow risk here since y < 2^136 after the first branch above.
            z := shr(18, mul(z, add(y, 65536))) // A mul() is saved from starting z at 181.

            // Given the worst case multiplicative error of 2.84 above, 7 iterations should be enough.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // If x+1 is a perfect square, the Babylonian method cycles between
            // floor(sqrt(x)) and ceil(sqrt(x)). This statement ensures we return floor.
            // See: https://en.wikipedia.org/wiki/Integer_square_root#Using_only_integer_division
            // Since the ceil is rare, we save gas on the assignment and repeat division in the rare case.
            // If you don't care whether the floor or ceil square root is returned, you can remove this statement.
            z := sub(z, lt(div(x, z), z))
        }
    }

    // Mul Div

    /// @dev Rounded down.
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    /// @dev Rounded down.
    /// This function assumes that `x` is not zero, and must be checked externally.
    function mulDivUnsafeFirst(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x * y) / x == y)
            if iszero(and(iszero(iszero(denominator)), eq(div(z, x), y))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    /// @dev Rounded down.
    /// This function assumes that `denominator` is not zero, and must be checked externally.
    function mulDivUnsafeLast(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(x == 0 || (x * y) / x == y)
            if iszero(or(iszero(x), eq(div(z, x), y))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    /// @dev Rounded down.
    /// This function assumes that both `x` and `denominator` are not zero, and must be checked externally.
    function mulDivUnsafeFirstLast(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require((x * y) / x == y)
            if iszero(eq(div(z, x), y)) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    // Mul

    /// @dev Optimized safe multiplication operation for minimal gas cost.
    /// Equivalent to *
    function mul(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(x == 0 || (x * y) / x == y)
            if iszero(or(iszero(x), eq(div(z, x), y))) {
                revert(0, 0)
            }
        }
    }

    /// @dev Optimized unsafe multiplication operation for minimal gas cost.
    /// This function assumes that `x` is not zero, and must be checked externally.
    function mulUnsafeFirst(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require((x * y) / x == y)
            if iszero(eq(div(z, x), y)) {
                revert(0, 0)
            }
        }
    }

    // Div

    /// @dev Optimized safe division operation for minimal gas cost.
    /// Equivalent to /
    function div(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := div(x, y)

            // Equivalent to require(y != 0)
            if iszero(y) {
                revert(0, 0)
            }
        }
    }

    /// @dev Optimized unsafe division operation for minimal gas cost.
    /// Division by 0 will not reverts and returns 0, and must be checked externally.
    function divUnsafeLast(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        assembly {
            z := div(x, y)
        }
    }
}


// File contracts/libraries/StableMath.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
library StableMath {
    /// @notice Calculate the new balances of the tokens given the indexes of the token
    /// that is swapped from (FROM) and the token that is swapped to (TO).
    /// This function is used as a helper function to calculate how much TO token
    /// the user should receive on swap.
    /// @dev Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L432.
    /// @param x The new total amount of FROM token.
    /// @return y The amount of TO token that should remain in the pool.
    function getY(uint x, uint d) internal pure returns (uint y) {
        //uint c = (d * d) / (x * 2);
        uint c = Math.mulDiv(d, d, Math.mulUnsafeFirst(2, x));
        //c = (c * d) / 4000;
        c = Math.mulDivUnsafeLast(c, d, 4000);
    
        //uint b = x + (d / 2000);
        uint b = x + Math.divUnsafeLast(d, 2000);
        uint yPrev;
        y = d;

        /// @dev Iterative approximation.
        for (uint i; i < 256; ) {
            yPrev = y;
            //y = (y * y + c) / (y * 2 + b - d);
            y = Math.div(Math.mul(y, y) + c, Math.mulUnsafeFirst(2, y) + b - d);

            if (Math.within1(y, yPrev)) {
                break;
            }

            unchecked {
                ++i;
            }
        }
    }

    function computeDFromAdjustedBalances(uint xp0, uint xp1) internal pure returns (uint computed) {
        uint s = xp0 + xp1;

        if (s == 0) {
            computed = 0;
        } else {
            uint prevD;
            uint d = s;

            for (uint i; i < 256; ) {
                //uint dP = (((d * d) / xp0) * d) / xp1 / 4;
                uint dP = Math.divUnsafeLast(Math.mulDiv(Math.mulDiv(d, d, xp0), d, xp1), 4);
                prevD = d;
                //d = (((2000 * s) + 2 * dP) * d) / ((2000 - 1) * d + 3 * dP);
                d = Math.mulDivUnsafeFirst(
                    // `s` cannot be zero and this value will never be zero.
                    Math.mulUnsafeFirst(2000, s) + Math.mulUnsafeFirst(2, dP),
                    d,
                    Math.mulUnsafeFirst(1999, d) + Math.mulUnsafeFirst(3, dP)
                );

                if (Math.within1(d, prevD)) {
                    break;
                }

                unchecked {
                    ++i;
                }
            }

            computed = d;
        }
    }
}


// File contracts/interfaces/factory/IPoolFactory.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPoolFactory {
    function master() external view returns (address);

    function getDeployData() external view returns (bytes memory);

    function createPool(bytes calldata data) external returns (address pool);
}


// File contracts/libraries/MetadataHelper.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

library MetadataHelper {
    /**
     * @dev Returns symbol of the token.
     *
     * @param token The address of a ERC20 token.
     *
     * Return boolean indicating the status and the symbol as string;
     *
     * NOTE: Symbol is not the standard interface and some tokens may not support it.
     * Calling against these tokens will not success, with an empty result.
     */
    function getSymbol(address token) internal view returns (bool, string memory) {
        // bytes4(keccak256(bytes("symbol()")))
        (bool success, bytes memory returndata) = token.staticcall(abi.encodeWithSelector(0x95d89b41));
        if (success) {
            return (true, abi.decode(returndata, (string)));
        } else {
            return (false, "");
        }
    }
}


// File contracts/libraries/ReentrancyGuard.sol

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}


// File contracts/interfaces/token/IERC165.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IERC165 {
    /// @notice Query if a contract implements an interface
    /// @param interfaceID The interface identifier, as specified in ERC-165
    /// @dev Interface identification is specified in ERC-165. This function
    ///  uses less than 30,000 gas.
    /// @return `true` if the contract implements `interfaceID` and
    ///  `interfaceID` is not 0xffffffff, `false` otherwise
    function supportsInterface(bytes4 interfaceID) external view returns (bool);
}


// File contracts/pool/SyncSwapLPToken.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
error Expired();
error InvalidSignature();

/**
 * @dev A simple ERC20 implementation for pool's liquidity token, supports permit by both ECDSA signatures from
 * externally owned accounts (EOAs) as well as ERC1271 signatures from smart contract wallets like Argent.
 *
 * Based on Solmate's ERC20.
 * https://github.com/transmissions11/solmate/blob/bff24e835192470ed38bf15dbed6084c2d723ace/src/tokens/ERC20.sol
 */
contract SyncSwapLPToken is IERC165, IERC20Permit2 {
    string public override name;
    string public override symbol;
    uint8 public immutable override decimals = 18;

    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;

    bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9; // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    mapping(address => uint) public override nonces;

    constructor() {
    }

    function _initializeMetadata(string memory _name, string memory _symbol) internal {
        name = _name;
        symbol = _symbol;
    }

    function supportsInterface(bytes4 interfaceID) external pure override returns (bool) {
        return
            interfaceID == this.supportsInterface.selector || // ERC-165
            interfaceID == this.permit.selector || // ERC-2612
            interfaceID == this.permit2.selector; // Permit2
    }

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                keccak256(bytes(name)),
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes("1"))
                block.chainid,
                address(this)
            )
        );
    }

    function _approve(address _owner, address _spender, uint _amount) private {
        allowance[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function approve(address _spender, uint _amount) public override returns (bool) {
        _approve(msg.sender, _spender, _amount);
        return true;
    }

    function transfer(address _to, uint _amount) public override returns (bool) {
        balanceOf[msg.sender] -= _amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint _amount) public override returns (bool) {
        uint256 _allowed = allowance[_from][msg.sender]; // Saves gas for limited approvals.
        if (_allowed != type(uint).max) {
            allowance[_from][msg.sender] = _allowed - _amount;
        }

        balanceOf[_from] -= _amount;
        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(_from, _to, _amount);
        return true;
    }

    function _mint(address _to, uint _amount) internal {
        totalSupply += _amount;

        // Cannot overflow because the sum of all user balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[_to] += _amount;
        }

        emit Transfer(address(0), _to, _amount);
    }

    function _burn(address _from, uint _amount) internal {
        balanceOf[_from] -= _amount;

        // Cannot underflow because a user's balance will never be larger than the total supply.
        unchecked {
            totalSupply -= _amount;
        }

        emit Transfer(_from, address(0), _amount);
    }

    modifier ensures(uint _deadline) {
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > _deadline) {
            revert Expired();
        }
        _;
    }

    function _permitHash(
        address _owner,
        address _spender,
        uint _amount,
        uint _deadline
    ) private returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _amount, nonces[_owner]++, _deadline))
            )
        );
    }

    function permit(
        address _owner,
        address _spender,
        uint _amount,
        uint _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public override ensures(_deadline) {
        bytes32 _hash = _permitHash(_owner, _spender, _amount, _deadline);
        address _recoveredAddress = ecrecover(_hash, _v, _r, _s);

        if (_recoveredAddress == address(0) || _recoveredAddress != _owner) {
            revert InvalidSignature();
        }

        _approve(_owner, _spender, _amount);
    }

    function permit2(
        address _owner,
        address _spender,
        uint _amount,
        uint _deadline,
        bytes calldata _signature
    ) public override ensures(_deadline) {
        bytes32 _hash = _permitHash(_owner, _spender, _amount, _deadline);

        if (!SignatureChecker.isValidSignatureNow(_owner, _hash, _signature)) {
            revert InvalidSignature();
        }

        _approve(_owner, _spender, _amount);
    }
}


// File contracts/pool/stable/SyncSwapStablePool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
error InsufficientLiquidityMinted();

contract SyncSwapStablePool is IStablePool, SyncSwapLPToken, ReentrancyGuard {
    using Math for uint;

    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.

    /// @dev Pool type `2` for stable pools.
    uint16 public constant override poolType = 2;

    address public immutable override master;
    address public immutable override vault;

    address public immutable override token0;
    address public immutable override token1;

    /// @dev Multipliers for each pooled token's precision to get to the pool precision decimals
    /// which is agnostic to the pool, but usually is 18.
    /// For example, TBTC has 18 decimals, so the multiplier should be 10 ** (18 - 18) = 1.
    /// WBTC has 8, so the multiplier should be 10 ** (18 - 8) => 10 ** 10.
    /// The value is only for stable pools, and has no effects on non-stable pools.
    uint public immutable override token0PrecisionMultiplier;
    uint public immutable override token1PrecisionMultiplier;

    /// @dev Pool reserve of each pool token as of immediately after the most recent balance event.
    /// The value is used to measure growth in invariant on mints and input tokens on swaps.
    uint public override reserve0;
    uint public override reserve1;

    /// @dev Invariant of the pool as of immediately after the most recent liquidity event.
    /// The value is used to measure growth in invariant when protocol fee is enabled,
    /// and will be reset to zero if protocol fee is disabled.
    uint public override invariantLast;

    /// @dev Factory must ensures that the parameters are valid.
    constructor() {
        (bytes memory _deployData) = IPoolFactory(msg.sender).getDeployData();
        (address _token0, address _token1, uint _token0PrecisionMultiplier, uint _token1PrecisionMultiplier) = abi.decode(
            _deployData, (address, address, uint, uint)
        );
        address _master = IPoolFactory(msg.sender).master();

        master = _master;
        vault = IPoolMaster(_master).vault();
        (token0, token1, token0PrecisionMultiplier, token1PrecisionMultiplier) = (
            _token0, _token1, _token0PrecisionMultiplier, _token1PrecisionMultiplier
        );

        // try to set symbols for the LP token
        (bool _success0, string memory _symbol0) = MetadataHelper.getSymbol(_token0);
        (bool _success1, string memory _symbol1) = MetadataHelper.getSymbol(_token1);
        if (_success0 && _success1) {
            _initializeMetadata(
                string(abi.encodePacked("SyncSwap ", _symbol0, "/", _symbol1, " Stable LP")),
                string(abi.encodePacked(_symbol0, "/", _symbol1, " sSLP"))
            );
        } else {
            _initializeMetadata(
                "SyncSwap Stable LP",
                "sSLP"
            );
        }
    }

    function getAssets() external view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(bytes calldata _data) external override nonReentrant returns (uint _liquidity) {
        address _to = abi.decode(_data, (address));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        uint _newInvariant = _computeInvariant(_balance0, _balance1);
        uint _amount0 = _balance0 - _reserve0;
        uint _amount1 = _balance1 - _reserve1;
        //require(_amount0 != 0 && _amount1 != 0); // unchecked to save gas as not necessary

        {
        // Adds mint fee to reserves (applies to invariant increase) if unbalanced.
        (uint _fee0, uint _fee1) = _unbalancedMintFee(_amount0, _amount1, _reserve0, _reserve1);
        _reserve0 += _fee0;
        _reserve1 += _fee1;
        }

        {
        // Calculates old invariant (where unbalanced fee added to) and, mint protocol fee if any.
        (bool _feeOn, uint _totalSupply, uint _oldInvariant) = _mintProtocolFee(_reserve0, _reserve1);

        if (_totalSupply == 0) {
            _liquidity = _newInvariant - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock on first mint.
        } else {
            // Calculates liquidity proportional to invariant growth.
            _liquidity = ((_newInvariant - _oldInvariant) * _totalSupply) / _oldInvariant;
        }

        // Mints liquidity for recipient.
        if (_liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(_to, _liquidity);

        // Updates reserves and last invariant with new balances.
        _updateReserves(_balance0, _balance1);

        if (_feeOn) {
            invariantLast = _newInvariant;
        }
        }

        emit Mint(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    /// @dev Burns LP tokens sent to this contract.
    /// The router should ensure that sufficient pool tokens are received.
    function burn(bytes calldata _data) external override nonReentrant returns (TokenAmount[] memory _amounts) {
        (address _to, uint8 _withdrawMode) = abi.decode(_data, (address, uint8));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;
        //require(_amount0 != 0 || _amount1 != 0); // unchecked to save gas, should be done through router.

        // Burns liquidity and transfers pool tokens.
        _burn(address(this), _liquidity);
        _transferTokens(token0, _to, _amount0, _withdrawMode);
        _transferTokens(token1, _to, _amount1, _withdrawMode);

        // Update reserves and last invariant with up-to-date balances (after transfers).
        /// @dev Using counterfactuals balances here to save gas.
        /// Cannot underflow because amounts will never be smaller than balances.
        unchecked {
            _balance0 -= _amount0;
            _balance1 -= _amount1;
        }
        _updateReserves(_balance0, _balance1);

        if (_feeOn) {
            invariantLast = _computeInvariant(_balance0, _balance1);
        }

        _amounts = new TokenAmount[](2);
        _amounts[0] = TokenAmount(token0, _amount0);
        _amounts[1] = TokenAmount(token1, _amount1);

        emit Burn(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    /// @dev Burns LP tokens sent to this contract and swaps one of the output tokens for another
    /// - i.e., the user gets a single token out by burning LP tokens.
    /// The router should ensure that sufficient pool tokens are received.
    function burnSingle(bytes calldata _data) external override nonReentrant returns (uint _amountOut) {
        (address _tokenOut, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;

        // Burns liquidity and, update last invariant using counterfactuals balances.
        _burn(address(this), _liquidity);

        // Swap one token for another, transfers desired tokens, and update context values.
        /// @dev Calculate `amountOut` as if the user first withdrew balanced liquidity and then swapped from one token for another.
        if (_tokenOut == token1) {
            // Swap `token0` for `token1`.
            _amount1 += _getAmountOut(_amount0, _balance0 - _amount0, _balance1 - _amount1, true);
            _transferTokens(token1, _to, _amount1, _withdrawMode);
            _amountOut = _amount1;
            _amount0 = 0;
            _balance1 -= _amount1;
        } else {
            // Swap `token1` for `token0`.
            require(_tokenOut == token0); // ensures to prevent from messing up the pool with bad parameters.
            _amount0 += _getAmountOut(_amount1, _balance0 - _amount0, _balance1 - _amount1, false);
            _transferTokens(token0, _to, _amount0, _withdrawMode);
            _amountOut = _amount0;
            _amount1 = 0;
            _balance0 -= _amount0;
        }

        // Update reserves and last invariant with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);

        if (_feeOn) {
            invariantLast = _computeInvariant(_balance0, _balance1);
        }

        emit Burn(msg.sender, _amount0, _amount1, _liquidity, _to);
    }

    /// @dev Swaps one token for another - should be called via the router after transferring input tokens.
    /// The router should ensure that sufficient output tokens are received.
    function swap(bytes calldata _data) external override nonReentrant returns (uint _amountOut) {
        (address _tokenIn, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        (uint _balance0, uint _balance1) = _balances();

        // Calculates output amount, update context values and emit event.
        uint _amountIn;
        address _tokenOut;
        if (_tokenIn == token0) {
            _tokenOut = token1;
            // Cannot underflow because reserve will never be larger than balance.
            unchecked {
                _amountIn = _balance0 - _reserve0;
            }
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, true);
            _balance1 -= _amountOut;

            emit Swap(msg.sender, _amountIn, 0, 0, _amountOut, _to);
        } else {
            //require(_tokenIn == token1);
            _tokenOut = token0;
            // Cannot underflow because reserve will never be larger than balance.
            unchecked {
                _amountIn = _balance1 - reserve1;
            }
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, false);
            _balance0 -= _amountOut;

            emit Swap(msg.sender, 0, _amountIn, _amountOut, 0, _to);
        }

        // Transfers output tokens.
        _transferTokens(_tokenOut, _to, _amountOut, _withdrawMode);

        // Update reserves with up-to-date balances (updated above).
        /// @dev Using counterfactuals balances here to save gas.
        _updateReserves(_balance0, _balance1);
    }

    function getSwapFee() public view override returns (uint24 _swapFee) {
        _swapFee = IPoolMaster(master).getSwapFee(address(this));
    }

    function getProtocolFee() public view override returns (uint24 _protocolFee) {
        _protocolFee = IPoolMaster(master).protocolFee(poolType);
    }

    function _updateReserves(uint _balance0, uint _balance1) private {
        (reserve0, reserve1) = (_balance0, _balance1);
        emit Sync(_balance0, _balance1);
    }

    function _transferTokens(address token, address to, uint amount, uint8 withdrawMode) private {
        if (withdrawMode == 0) {
            IVault(vault).transfer(token, to, amount);
        } else {
            IVault(vault).withdrawAlternative(token, to, amount, withdrawMode);
        }
    }

    function _balances() private view returns (uint balance0, uint balance1) {
        balance0 = IVault(vault).balanceOf(token0, address(this));
        balance1 = IVault(vault).balanceOf(token1, address(this));
    }

    /// @dev This fee is charged to cover for the swap fee when users add unbalanced liquidity.
    function _unbalancedMintFee(
        uint _amount0,
        uint _amount1,
        uint _reserve0,
        uint _reserve1
    ) private view returns (uint _token0Fee, uint _token1Fee) {
        if (_reserve0 == 0 || _reserve1 == 0) {
            return (0, 0);
        }
        uint _amount1Optimal = (_amount0 * _reserve1) / _reserve0;
        if (_amount1 >= _amount1Optimal) {
            _token1Fee = (getSwapFee() * (_amount1 - _amount1Optimal)) / (2 * MAX_FEE);
        } else {
            uint _amount0Optimal = (_amount1 * _reserve0) / _reserve1;
            _token0Fee = (getSwapFee() * (_amount0 - _amount0Optimal)) / (2 * MAX_FEE);
        }
    }

    function _mintProtocolFee(uint _reserve0, uint _reserve1) private returns (bool _feeOn, uint _totalSupply, uint _invariant) {
        _totalSupply = totalSupply;
        _invariant = _computeInvariant(_reserve0, _reserve1);

        address _feeRecipient = IPoolMaster(master).feeRecipient();
        _feeOn = (_feeRecipient != address(0));

        uint _invariantLast = invariantLast;
        if (_invariantLast != 0) {
            if (_feeOn) {
                if (_invariant > _invariantLast) {
                    /// @dev Mints `protocolFee` % of growth in liquidity (invariant).
                    uint _protocolFee = getProtocolFee();
                    uint _numerator = _totalSupply * (_invariant - _invariantLast) * _protocolFee;
                    uint _denominator = (MAX_FEE - _protocolFee) * _invariant + _protocolFee * _invariantLast;
                    uint _liquidity = _numerator / _denominator;

                    if (_liquidity != 0) {
                        _mint(_feeRecipient, _liquidity);
                        _totalSupply += _liquidity; // update cached value.
                    }
                }
            } else {
                /// @dev Reset last invariant to clear measured growth if protocol fee is not enabled.
                invariantLast = 0;
            }
        }
    }

    function getReserves() external view override returns (uint _reserve0, uint _reserve1) {
        (_reserve0, _reserve1) = (reserve0, reserve1);
    }

    function getAmountOut(address _tokenIn, uint _amountIn) external view override returns (uint _finalAmountOut) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        _finalAmountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, _tokenIn == token0);
    }

    function getAmountIn(address _tokenOut, uint _amountOut) external view override returns (uint _finalAmountIn) {
        (uint _reserve0, uint _reserve1) = (reserve0, reserve1);
        _finalAmountIn = _getAmountIn(_amountOut, _reserve0, _reserve1, _tokenOut == token0);
    }

    function _getAmountOut(
        uint _amountIn,
        uint _reserve0,
        uint _reserve1,
        bool _token0In
    ) private view returns (uint _dy) {
        if (_amountIn == 0) {
            _dy = 0;
        } else {
            unchecked {
                uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                uint _feeDeductedAmountIn = _amountIn - (_amountIn * getSwapFee()) / MAX_FEE;
                uint _d = StableMath.computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                if (_token0In) {
                    uint _x = _adjustedReserve0 + (_feeDeductedAmountIn * token0PrecisionMultiplier);
                    uint _y = StableMath.getY(_x, _d);
                    _dy = _adjustedReserve1 - _y - 1;
                    _dy /= token1PrecisionMultiplier;
                } else {
                    uint _x = _adjustedReserve1 + (_feeDeductedAmountIn * token1PrecisionMultiplier);
                    uint _y = StableMath.getY(_x, _d);
                    _dy = _adjustedReserve0 - _y - 1;
                    _dy /= token0PrecisionMultiplier;
                }
            }
        }
    }

    function _getAmountIn(
        uint _amountOut,
        uint _reserve0,
        uint _reserve1,
        bool _token0Out
    ) private view returns (uint _dx) {
        if (_amountOut == 0) {
            _dx = 0;
        } else {
            unchecked {
                uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
                uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
                uint _d = StableMath.computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);

                if (_token0Out) {
                    uint _y = _adjustedReserve0 - (_amountOut * token0PrecisionMultiplier);
                    if (_y <= 1) {
                        return 1;
                    }
                    uint _x = StableMath.getY(_y, _d);
                    _dx = MAX_FEE * (_x - _adjustedReserve1) / (MAX_FEE - getSwapFee()) + 1;
                    _dx /= token1PrecisionMultiplier;
                } else {
                    uint _y = _adjustedReserve1 - (_amountOut * token1PrecisionMultiplier);
                    if (_y <= 1) {
                        return 1;
                    }
                    uint _x = StableMath.getY(_y, _d);
                    _dx = MAX_FEE * (_x - _adjustedReserve0) / (MAX_FEE - getSwapFee()) + 1;
                    _dx /= token0PrecisionMultiplier;
                }
            }
        }
    }

    function _computeInvariant(uint _reserve0, uint _reserve1) private view returns (uint _invariant) {
        /// @dev Get D, the StableSwap invariant, based on a set of balances and a particular A.
        /// See the StableSwap paper for details.
        /// Originally https://github.com/saddle-finance/saddle-contract/blob/0b76f7fb519e34b878aa1d58cffc8d8dc0572c12/contracts/SwapUtils.sol#L319.
        /// Returns the invariant, at the precision of the pool.
        unchecked {
            uint _adjustedReserve0 = _reserve0 * token0PrecisionMultiplier;
            uint _adjustedReserve1 = _reserve1 * token1PrecisionMultiplier;
            _invariant = StableMath.computeDFromAdjustedBalances(_adjustedReserve0, _adjustedReserve1);
        }
    }
}
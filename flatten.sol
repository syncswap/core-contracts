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
    function nonces(address owner) external view returns (uint);
    function permit(address owner, address spender, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}


// File contracts/interfaces/token/IERC20Permit2.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IERC20Permit2 is IERC20Permit {
    function permit2(address owner, address spender, uint amount, uint deadline, bytes calldata signature) external;
}


// File contracts/abstract/SelfPermit.sol

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;
abstract contract SelfPermit {
    function selfPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable {
        IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
    }

    function selfPermitIfNecessary(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external payable {
        if (IERC20(token).allowance(msg.sender, address(this)) < value) {
            selfPermit(token, value, deadline, v, r, s);
        }
    }

    function selfPermit2(
        address token,
        uint256 value,
        uint256 deadline,
        bytes calldata signature
    ) public payable {
        IERC20Permit2(token).permit2(msg.sender, address(this), value, deadline, signature);
    }

    function selfPermit2IfNecessary(
        address token,
        uint256 value,
        uint256 deadline,
        bytes calldata signature
    ) external payable {
        if (IERC20(token).allowance(msg.sender, address(this)) < value) {
            selfPermit2(token, value, deadline, signature);
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


// File contracts/interfaces/factory/IBasePoolFactory.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IBasePoolFactory is IPoolFactory {
    event PoolCreated(
        address indexed token0,
        address indexed token1,
        address pool
    );

    function getPool(address tokenA, address tokenB) external view returns (address pool);

    function getSwapFee(address pool) external view returns (uint24 swapFee);
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


// File contracts/interfaces/pool/IClassicPool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IClassicPool is IBasePool {
}


// File contracts/interfaces/pool/IStablePool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;
interface IStablePool is IBasePool {
    function token0PrecisionMultiplier() external view returns (uint);
    function token1PrecisionMultiplier() external view returns (uint);
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


// File contracts/interfaces/IPoolMaster.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

/// @dev The master contract to control fees, create pools and manage whitelisted factories.
/// Management functions are omitted.
interface IPoolMaster {
    // Events
    event SetDefaultSwapFee(uint16 indexed poolType, uint24 defaultSwapFee);

    event SetCustomSwapFee(address indexed pool, uint24 customSwapFee);

    event SetProtocolFee(uint16 indexed poolType, uint24 protocolFee);

    event SetFeeRecipient(address indexed previousFeeRecipient, address indexed newFeeRecipient);

    event SetFactoryWhitelisted(address indexed factory, bool whitelisted);

    event RegisterPool(
        address indexed factory,
        address indexed pool,
        uint16 indexed poolType,
        bytes data
    );

    function vault() external view returns (address);

    // Fees
    function defaultSwapFee(uint16 poolType) external view returns (uint24);

    function customSwapFee(address pool) external view returns (uint24);

    function feeRecipient() external view returns (address);

    function protocolFee(uint16 poolType) external view returns (uint24);
    
    function getSwapFee(address pool) external view returns (uint24 swapFee);

    // Factories
    function isFactoryWhitelisted(address) external view returns (bool);

    // Pools
    function isPool(address) external view returns (bool);

    function getPool(bytes32) external view returns (address);

    function createPool(address factory, bytes calldata data) external returns (address pool);

    function registerPool(address pool, uint16 poolType, bytes calldata data) external;
}


// File contracts/libraries/Ownable.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error NotOwner();
error NotPendingOwner();

abstract contract Ownable {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(msg.sender);
    }

    modifier onlyOwner() {
        if (owner != msg.sender) {
            revert NotOwner();
        }
        _;
    }

    function setPendingOwner(address newPendingOwner) external onlyOwner {
        pendingOwner = newPendingOwner;
    }

    function acceptOwnership() external {
        address _pendingOwner = pendingOwner;
        if (_pendingOwner != msg.sender) {
            revert NotPendingOwner();
        }
        _transferOwnership(_pendingOwner);
        delete pendingOwner;
    }

    function _transferOwnership(address newOwner) private {
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}


// File contracts/pool/BasePoolFactory.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
error NotPoolMaster();
error InvalidTokens();
error InvalidFee();

abstract contract BasePoolFactory is IBasePoolFactory, Ownable {
    /// @dev The pool master that control fees and registry.
    address public immutable master;

    /// @dev Pools by its two pool tokens.
    mapping(address => mapping(address => address)) public override getPool;

    bytes internal cachedDeployData;

    constructor(address _master) {
        master = _master;
    }

    function getDeployData() external view override returns (bytes memory deployData) {
        deployData = cachedDeployData;
    }

    function getSwapFee(address pool) external view override returns (uint24 swapFee) {
        swapFee = IPoolMaster(master).getSwapFee(pool);
    }

    function createPool(bytes calldata data) external override returns (address pool) {
        (address tokenA, address tokenB) = abi.decode(data, (address, address));

        // Perform safety checks.
        if (tokenA == tokenB) {
            revert InvalidTokens();
        }

        // Sort tokens.
        if (tokenB < tokenA) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }
        if (tokenA == address(0)) {
            revert InvalidTokens();
        }

        // Underlying implementation to deploy the pools and register them.
        pool = _createPool(tokenA, tokenB);

        // Populate mapping in both directions.
        // Not necessary as existence of the master, but keep them for better compatibility.
        getPool[tokenA][tokenB] = pool;
        getPool[tokenB][tokenA] = pool;

        emit PoolCreated(tokenA, tokenB, pool);
    }

    function _createPool(address tokenA, address tokenB) internal virtual returns (address) {
    }
}


// File contracts/interfaces/IVault.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IVault {
    function wETH() external view returns (address);

    function reserves(address token) external view returns (uint reserve);

    function balanceOf(address token, address owner) external view returns (uint balance);

    function deposit(address token, address to) external payable returns (uint amount);

    function depositETH(address to) external payable returns (uint amount);

    function transferAndDeposit(address token, address to, uint amount) external payable;

    function transfer(address token, address to, uint amount) external;

    function withdraw(address token, address to, uint amount) external;

    function withdrawAlternative(address token, address to, uint amount, uint8 mode) external;

    function withdrawETH(address to, uint amount) external;
}


// File contracts/libraries/Lock.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error Locked();

/// @dev A simple reentrancy lock.
abstract contract Lock {
    uint8 private unlocked = 1;
    
    modifier lock() {
        if (unlocked == 0) {
            revert Locked();
        }
        unlocked = 0;
        _;
        unlocked = 1;
    }
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
contract SyncSwapLPToken is IERC20Permit2 {
    string public constant override name = "SyncSwap LP Token";
    string public constant override symbol = "SSLP";
    uint8 public immutable override decimals = 18;

    uint public override totalSupply;
    mapping(address => uint) public override balanceOf;
    mapping(address => mapping(address => uint)) public override allowance;
    
    bytes32 private immutable domainSeparator;
    bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9; // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    mapping(address => uint) public override nonces;

    constructor() {
        domainSeparator = keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x125767caed758c30726816e62c5b217c6b2b9320c3afbe187788f2fe0d76e810, // keccak256(bytes("SyncSwap LP Token"))
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
                domainSeparator,
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


// File contracts/pool/classic/SyncSwapClassicPool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
error InsufficientLiquidityMinted();

contract SyncSwapClassicPool is IClassicPool, SyncSwapLPToken, Lock {
    using Math for uint;

    uint private constant MINIMUM_LIQUIDITY = 1000;
    uint private constant MAX_FEE = 1e5; /// @dev 100%.

    /// @dev Pool type `1` for classic pools.
    uint16 public constant override poolType = 1;

    address public immutable override master;
    address public immutable override vault;

    address public immutable override token0;
    address public immutable override token1;

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
        (address _token0, address _token1) = abi.decode(_deployData, (address, address));
        address _master = IPoolFactory(msg.sender).master();

        master = _master;
        vault = IPoolMaster(_master).vault();
        (token0, token1) = (_token0, _token1);
    }

    function getAssets() external view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(bytes calldata _data) external override lock returns (uint _liquidity) {
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
    function burn(bytes calldata _data) external override lock returns (TokenAmount[] memory _amounts) {
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
    function burnSingle(bytes calldata _data) external override lock returns (uint _amountOut) {
        (address _tokenOut, address _to, uint8 _withdrawMode) = abi.decode(_data, (address, address, uint8));
        (uint _balance0, uint _balance1) = _balances();
        uint _liquidity = balanceOf[address(this)];

        // Mints protocol fee if any.
        (bool _feeOn, uint _totalSupply, ) = _mintProtocolFee(_balance0, _balance1);

        // Calculates amounts of pool tokens proportional to balances.
        uint _amount0 = _liquidity * _balance0 / _totalSupply;
        uint _amount1 = _liquidity * _balance1 / _totalSupply;

        // Burns liquidity.
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
    function swap(bytes calldata _data) external override lock returns (uint _amountOut) {
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

            emit Swap(msg.sender, _amountIn, 0, 0, _amountOut, _to); // emit here to avoid checking direction 
        } else {
            require(_tokenIn == token1); // ensures to prevent counterfeit event parameters.
            _tokenOut = token0;
            // Cannot underflow because reserve will never be larger than balance.
            unchecked {
                _amountIn = _balance1 - reserve1;
            }
            _amountOut = _getAmountOut(_amountIn, _reserve0, _reserve1, false);
            _balance0 -= _amountOut;

            emit Swap(msg.sender, 0, _amountIn, _amountOut, 0, _to); // emit here to avoid checking direction 
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

    function getAmountIn(address _tokenOut, uint256 _amountOut) external view override returns (uint _finalAmountIn) {
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
            uint _amountInWithFee = _amountIn * (MAX_FEE - getSwapFee());
            if (_token0In) {
                _dy = (_amountInWithFee * _reserve1) / (_reserve0 * MAX_FEE + _amountInWithFee);
            } else {
                _dy = (_amountInWithFee * _reserve0) / (_reserve1 * MAX_FEE + _amountInWithFee);
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
            if (_token0Out) {
                _dx = (_reserve1 * _amountOut * MAX_FEE) / ((_reserve0 - _amountOut) * (MAX_FEE - getSwapFee())) + 1;
            } else {
                _dx = (_reserve0 * _amountOut * MAX_FEE) / ((_reserve1 - _amountOut) * (MAX_FEE - getSwapFee())) + 1;
            }
        }
    }

    function _computeInvariant(uint _reserve0, uint _reserve1) private pure returns (uint _invariant) {
        _invariant = (_reserve0 * _reserve1).sqrt();
    }
}


// File contracts/pool/classic/SyncSwapClassicPoolFactory.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
contract SyncSwapClassicPoolFactory is BasePoolFactory {
    constructor(address _master) BasePoolFactory(_master) {
    }

    function _createPool(address token0, address token1) internal override returns (address pool) {
        // Perform sanity checks.
        IERC20(token0).balanceOf(address(this));
        IERC20(token1).balanceOf(address(this));

        bytes memory deployData = abi.encode(token0, token1);
        cachedDeployData = deployData;

        // The salt is same with deployment data.
        bytes32 salt = keccak256(deployData);
        pool = address(new SyncSwapClassicPool{salt: salt}()); // this will prevent duplicated pools.

        // Register the pool. The config is same with deployment data.
        IPoolMaster(master).registerPool(pool, 1, deployData);
    }
}


// File contracts/pool/stable/SyncSwapStablePool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
error InsufficientLiquidityMinted();

contract SyncSwapStablePool is IStablePool, SyncSwapLPToken, Lock {
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
    }

    function getAssets() external view override returns (address[] memory assets) {
        assets = new address[](2);
        assets[0] = token0;
        assets[1] = token1;
    }

    /// @dev Mints LP tokens - should be called via the router after transferring pool tokens.
    /// The router should ensure that sufficient LP tokens are minted.
    function mint(bytes calldata _data) external override lock returns (uint _liquidity) {
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
    function burn(bytes calldata _data) external override lock returns (TokenAmount[] memory _amounts) {
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
    function burnSingle(bytes calldata _data) external override lock returns (uint _amountOut) {
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
    function swap(bytes calldata _data) external override lock returns (uint _amountOut) {
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

    function getAmountIn(address _tokenOut, uint256 _amountOut) external view override returns (uint _finalAmountIn) {
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


// File contracts/pool/stable/SyncSwapStablePoolFactory.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
contract SyncSwapStablePoolFactory is BasePoolFactory {
    constructor(address _master) BasePoolFactory(_master) {
    }

    function _createPool(address token0, address token1) internal override returns (address pool) {
        // Tokens with decimals more than 18 are not supported and will lead to reverts.
        uint token0PrecisionMultiplier = 10 ** (18 - IERC20(token0).decimals());
        uint token1PrecisionMultiplier = 10 ** (18 - IERC20(token1).decimals());

        bytes memory deployData = abi.encode(token0, token1, token0PrecisionMultiplier, token1PrecisionMultiplier);
        cachedDeployData = deployData;

        // Remove precision multipliers from salt and config.
        deployData = abi.encode(token0, token1);

        bytes32 salt = keccak256(deployData);
        pool = address(new SyncSwapStablePool{salt: salt}()); // this will prevent duplicated pools.

        // Register the pool with config.
        IPoolMaster(master).registerPool(pool, 2, deployData);
    }
}


// File contracts/SyncSwapPoolMaster.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
error NotWhitelistedFactory();
error InvalidFee();
error PoolAlreadyExists();

/// @notice The pool master manages swap fees for pools, whitelist for factories,
/// protocol fee and pool registry.
///
/// It accepts pool registers from whitelisted factories, with the pool data on pool
/// creation, to enable querying of the existence or fees of a pool by address or config.
///
/// This contract provides a unified interface to query and manage fees across
/// different pool types, and a unique registry for all pools.
///
contract SyncSwapPoolMaster is IPoolMaster, Ownable {
    uint24 private constant MAX_FEE = 1e5; /// @dev 100%.
    uint24 private constant MAX_SWAP_FEE = 10000; /// @dev 10%.
    uint24 private constant ZERO_CUSTOM_SWAP_FEE = type(uint24).max;

    /// @dev The vault that holds funds.
    address public immutable override vault;

    // Fees

    /// @dev The default swap fee by pool type.
    mapping(uint16 => uint24) public override defaultSwapFee; /// @dev `300` for 0.3%.

    /// @dev The custom swap fee by pool address, use `ZERO_CUSTOM_SWAP_FEE` for zero fee.
    mapping(address => uint24) public override customSwapFee;

    /// @dev The recipient of protocol fees.
    address public override feeRecipient;

    /// @dev The protocol fee of swap fee by pool type.
    mapping(uint16 => uint24) public override protocolFee; /// @dev `30000` for 30%.

    // Factories

    /// @dev Whether an address is a factory.
    mapping(address => bool) public override isFactoryWhitelisted;

    // Pools

    /// @dev Whether an address is a pool.
    mapping(address => bool) public override isPool;

    /// @dev Pools by hash of its config.
    mapping(bytes32 => address) public getPool;

    constructor(address _vault, address _feeRecipient) {
        vault = _vault;
        feeRecipient = _feeRecipient;

        // Prefill fees for known pool types.
        // Classic pools.
        defaultSwapFee[1] = 300; // 0.3%.
        protocolFee[1] = 30000; // 30%.

        // Stable pools.
        defaultSwapFee[2] = 100; // 0.1%.
        protocolFee[2] = 50000; // 50%.
    }

    // Fees

    function getSwapFee(address pool) external view override returns (uint24 swapFee) {
        uint24 _customSwapFee = customSwapFee[pool];

        if (_customSwapFee == 0) {
            swapFee = defaultSwapFee[IPool(pool).poolType()]; // use default instead if not set.
        } else {
            swapFee = (_customSwapFee == ZERO_CUSTOM_SWAP_FEE ? 0 : _customSwapFee);
        }
    }

    function setDefaultSwapFee(uint16 poolType, uint24 _defaultSwapFee) external onlyOwner {
        if (_defaultSwapFee > MAX_SWAP_FEE) {
            revert InvalidFee();
        }
        defaultSwapFee[poolType] = _defaultSwapFee;
        emit SetDefaultSwapFee(poolType, _defaultSwapFee);
    }

    function setCustomSwapFee(address pool, uint24 _customSwapFee) external onlyOwner {
        if (_customSwapFee > MAX_SWAP_FEE && _customSwapFee != ZERO_CUSTOM_SWAP_FEE) {
            revert InvalidFee();
        }
        customSwapFee[pool] = _customSwapFee;
        emit SetCustomSwapFee(pool, _customSwapFee);
    }

    function setProtocolFee(uint16 poolType, uint24 _protocolFee) external onlyOwner {
        if (_protocolFee > MAX_FEE) {
            revert InvalidFee();
        }
        protocolFee[poolType] = _protocolFee;
        emit SetProtocolFee(poolType, _protocolFee);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        // Emit here to avoid caching the previous recipient.
        emit SetFeeRecipient(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    // Factories

    function setFactoryWhitelisted(address factory, bool whitelisted) external onlyOwner {
        isFactoryWhitelisted[factory] = whitelisted;
        emit SetFactoryWhitelisted(factory, whitelisted);
    }

    // Pools

    /// @dev Create a pool with deployment data and, register it via the factory.
    function createPool(address factory, bytes calldata data) external override returns (address pool) {
        // The factory have to call `registerPool` to register the pool.
        // The pool whitelist is checked in `registerPool`.
        pool = IPoolFactory(factory).createPool(data);
    }

    /// @dev Register a pool to the mapping by its config. Can only be called by factories.
    function registerPool(address pool, uint16 poolType, bytes calldata data) external override {
        if (!isFactoryWhitelisted[msg.sender]) {
            revert NotWhitelistedFactory();
        }

        require(pool != address(0));

        // Double check to prevent duplicated pools.
        if (isPool[pool]) {
            revert PoolAlreadyExists();
        }

        // Encode and hash pool config to get the mapping key.
        bytes32 hash = keccak256(abi.encode(poolType, data));

        // Double check to prevent duplicated pools.
        if (getPool[hash] != address(0)) {
            revert PoolAlreadyExists();
        }

        // Set to mappings.
        getPool[hash] = pool;
        isPool[pool] = true;

        emit RegisterPool(msg.sender, pool, poolType, data);
    }
}


// File contracts/abstract/Multicall.sol

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice Helper utility that enables calling multiple local methods in a single call.
/// @author Modified from Uniswap (https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol)
/// License-Identifier: GPL-2.0-or-later
abstract contract Multicall {
    function multicall(bytes[] calldata data) public payable returns (bytes[] memory results) {
        results = new bytes[](data.length);
        
        for (uint256 i; i < data.length;) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;

            // cannot realistically overflow on human timescales
            unchecked {
                ++i;
            }
        }
    }
}


// File contracts/interfaces/IRouter.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IRouter {
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


// File contracts/interfaces/IStakingPool.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IStakingPool {
    function stake(uint amount, address onBehalf) external;
}


// File contracts/interfaces/IWETH.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function withdraw(uint) external;
}


// File contracts/libraries/TransferHelper.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

error SafeApproveFailed();
error SafeTransferFailed();
error SafeTransferFromFailed();
error SafeTransferETHFailed();

/// @dev Helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true / false.
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes("approve(address,uint256)")));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));

        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeApproveFailed();
        }
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes("transfer(address,uint256)")));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));

        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFailed();
        }
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes("transferFrom(address,address,uint256)")));
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));

        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert SafeTransferFromFailed();
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, ) = to.call{value: value}(new bytes(0));

        if (!success) {
            revert SafeTransferETHFailed();
        }
    }
}


// File contracts/SyncSwapRouter.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
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


// File contracts/SyncSwapVault.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;
/// @notice The vault stores all tokens supporting internal transfers to save gas.
contract SyncSwapVault is IVault, Lock {

    address private constant NATIVE_ETH = address(0);
    address public immutable override wETH;

    mapping(address => mapping(address => uint)) private balances;
    mapping(address => uint) public override reserves;

    constructor(address _wETH) {
        wETH = _wETH;
    }

    receive() external payable {
        // Deposit ETH via fallback if not from the wETH withdraw.
        if (msg.sender != wETH) {
            deposit(NATIVE_ETH, msg.sender);
        }
    }

    function balanceOf(address token, address owner) external view override returns (uint balance) {
        // Ensure the same `balances` as native ETH.
        if (token == wETH) {
            token = NATIVE_ETH;
        }

        return balances[token][owner];
    }

    // Deposit

    function deposit(address token, address to) public payable override lock returns (uint amount) {
        if (token == NATIVE_ETH) {
            // Use `msg.value` as amount for native ETH.
            amount = msg.value;
        } else {
            require(msg.value == 0);

            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                // Use balance as amount for wETH.
                amount = IERC20(wETH).balanceOf(address(this));

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            } else {
                // Derive real amount with balance and reserve for ERC20 tokens.
                amount = IERC20(token).balanceOf(address(this)) - reserves[token];
            }
        }

        // Increase token reserve.
        reserves[token] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `reserves` doesn't overflow.
            balances[token][to] += amount;
        }
    }

    function depositETH(address to) external payable override lock returns (uint amount) {
        // Use `msg.value` as amount for native ETH.
        amount = msg.value;

        // Increase token reserve.
        reserves[NATIVE_ETH] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `reserves` doesn't overflow.
            balances[NATIVE_ETH][to] += amount;
        }
    }

    // Transfer tokens from sender and deposit, requires approval.
    function transferAndDeposit(address token, address to, uint amount) external payable override lock {
        if (token == NATIVE_ETH) {
            require(amount == msg.value);
        } else {
            require(msg.value == 0);

            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                // Receive wETH from sender.
                IWETH(wETH).transferFrom(msg.sender, address(this), amount);

                // Unwrap wETH to native ETH.
                IWETH(wETH).withdraw(amount);
            } else {
                // Receive ERC20 tokens from sender.
                TransferHelper.safeTransferFrom(token, msg.sender, address(this), amount);

                // Derive real amount with balance and reserve for ERC20 tokens.
                amount = IERC20(token).balanceOf(address(this)) - reserves[token];
            }
        }

        // Increase token reserve.
        reserves[token] += amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `reserves` doesn't overflow.
            balances[token][to] += amount;
        }
    }

    // Transfer

    function transfer(address token, address to, uint amount) external override lock {
        // Ensure the same `reserves` and `balances` as native ETH.
        if (token == wETH) {
            token = NATIVE_ETH;
        }

        // Decrease token balance for sender.
        balances[token][msg.sender] -= amount;

        // Increase token balance for recipient.
        unchecked {
            /// `balances` cannot overflow if `balances` doesn't underflow.
            balances[token][to] += amount;
        }
    }

    // Withdraw

    function _wrapAndTransferWETH(address to, uint amount) private {
        // Wrap native ETH to wETH.
        IWETH(wETH).deposit{value: amount}();

        // Send wETH to recipient.
        IWETH(wETH).transfer(to, amount);
    }

    function withdraw(address token, address to, uint amount) external override lock {
        if (token == NATIVE_ETH) {
            // Send native ETH to recipient.
            TransferHelper.safeTransferETH(to, amount);
        } else {
            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                _wrapAndTransferWETH(to, amount);
            } else {
                // Send ERC20 tokens to recipient.
                TransferHelper.safeTransfer(token, to, amount);
            }
        }

        // Decrease token balance for sender.
        balances[token][msg.sender] -= amount;

        // Decrease token reserve.
        unchecked {
            /// `reserves` cannot underflow if `balances` doesn't underflow.
            reserves[token] -= amount;
        }
    }

    // Withdraw with mode.
    // 0 = DEFAULT
    // 1 = UNWRAPPED
    // 2 = WRAPPED
    function withdrawAlternative(address token, address to, uint amount, uint8 mode) external override lock {
        if (token == NATIVE_ETH) {
            if (mode == 2) {
                _wrapAndTransferWETH(to, amount);
            } else {
                // Send native ETH to recipient.
                TransferHelper.safeTransferETH(to, amount);
            }
        } else {
            if (token == wETH) {
                // Ensure the same `reserves` and `balances` as native ETH.
                token = NATIVE_ETH;

                if (mode == 1) {
                    // Send native ETH to recipient.
                    TransferHelper.safeTransferETH(to, amount);
                } else {
                    _wrapAndTransferWETH(to, amount);
                }
            } else {
                // Send ERC20 tokens to recipient.
                TransferHelper.safeTransfer(token, to, amount);
            }
        }

        // Decrease token balance for sender.
        balances[token][msg.sender] -= amount;

        // Decrease token reserve.
        unchecked {
            /// `reserves` cannot underflow if `balances` doesn't underflow.
            reserves[token] -= amount;
        }
    }

    function withdrawETH(address to, uint amount) external override lock {
        // Send native ETH to recipient.
        TransferHelper.safeTransferETH(to, amount);

        // Decrease token balance for sender.
        balances[NATIVE_ETH][msg.sender] -= amount;

        // Decrease token reserve.
        unchecked {
            /// `reserves` cannot underflow if `balances` doesn't underflow.
            reserves[NATIVE_ETH] -= amount;
        }
    }
}


// File contracts/test/RouterEventEmitter.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;


contract RouterEventEmitter is IRouter {

    address public immutable vault;
    address public immutable wETH;
    address private constant NATIVE_ETH = address(0);

    constructor(address _vault, address _wETH) {
        vault = _vault;
        wETH = _wETH;
    }

    event Amounts(uint amount);

    receive() external payable {}

    function swap(
        address payable router,
        SwapPath[] memory paths,
        uint amountOutMin,
        uint deadline
    ) external {
        (bool success, bytes memory returnData) = router.delegatecall(abi.encodeWithSelector(
            SyncSwapRouter(router).swap.selector,
            paths,
            amountOutMin,
            deadline
        ));
        assert(success);
        emit Amounts(abi.decode(returnData, (uint)));
    }
}


// File contracts/test/TestSyncSwapLPToken.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

contract TestSyncSwapLPToken is SyncSwapLPToken {
    constructor(uint _totalSupply) {
        _mint(msg.sender, _totalSupply);
    }
}


// File contracts/test/DeflatingERC20.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

contract DeflatingERC20 {
    string public constant name = "Deflating Test Token";
    string public constant symbol = "DTT";
    uint8 public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor(uint _totalSupply) {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
        _mint(msg.sender, _totalSupply);
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply + value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from] - value;
        totalSupply = totalSupply - value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        uint burnAmount = value / 100;
        _burn(from, burnAmount);
        uint transferAmount = value - burnAmount;
        balanceOf[from] = balanceOf[from] - transferAmount;
        balanceOf[to] = balanceOf[to] + transferAmount;
        emit Transfer(from, to, transferAmount);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint).max) {
            allowance[from][msg.sender] = allowance[from][msg.sender] - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}


// File contracts/test/TestERC20.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

contract TestERC20 {
    string public constant name = "Test Token";
    string public constant symbol = "TT";
    uint8 public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    constructor(uint _totalSupply) {
        uint chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
        _mint(msg.sender, _totalSupply);
    }

    function _mint(address to, uint value) internal {
        totalSupply = totalSupply + value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from] - value;
        totalSupply = totalSupply - value;
        emit Transfer(from, address(0), value);
    }

    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from] - value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(from, to, value);
    }

    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint).max) {
            allowance[from][msg.sender] = allowance[from][msg.sender] - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, "EXPIRED");
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNATURE");
        _approve(owner, spender, value);
    }
}


// File contracts/test/TestWETH9.sol

// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

contract TestWETH9 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8  public decimals = 18;

    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);
    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint wad) public {
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    function totalSupply() public view returns (uint) {
        return address(this).balance;
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad) public returns (bool) {
        if (src != msg.sender && allowance[src][msg.sender] != type(uint).max) {
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }
}

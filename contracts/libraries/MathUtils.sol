// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.0;

/// @notice A library that contains functions for calculating differences between two uint256.
/// @author Adapted from https://github.com/saddle-finance/saddle-contract/blob/master/contracts/MathUtils.sol.
library MathUtils {
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

    /// @dev Optimized multiply for minimal gas cost.
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
}





// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.0;

contract RoundTest {
    function round() external view returns (uint) {
        return uint(5) / 3; // 2.5
    }

    function max() external view returns (uint) {
        return type(uint16).max;
    }

    function uint232max() external view returns (uint) {
        return type(uint232).max;
    }

    function mulDivSolidity(uint x, uint y, uint z) external view returns (uint) {
        return x * y / z;
    }

    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) external pure returns (uint256 z) {
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

    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) external pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // First, divide z - 1 by the denominator and add 1.
            // We allow z - 1 to underflow if z is 0, because we multiply the
            // end result by 0 if z is zero, ensuring we return 0 if z is zero.
            z := mul(iszero(iszero(z)), add(div(sub(z, 1), denominator), 1))
        }
    }
}

contract MulDivVanilla {
    function mulDivSolidity(uint x, uint y, uint z) external view returns (uint) {
        return x * y / z;
    }
}

contract MulDivGas {
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) public pure returns (uint256 z) {
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

    function within1(uint256 a, uint256 b) internal pure returns (bool) {
        unchecked {
            if (a > b) {
                return a - b <= 1;
            }
            return b - a <= 1;
        }
    }

    function _D(uint _xp0, uint _xp1) external pure returns (uint _computed) {
        uint _s = _xp0 + _xp1;

        if (_s == 0) {
            _computed = 0;
        } else {
            uint _prevD;
            uint _d = _s;
            for (uint i; i < 256; ) {
                uint _dP = (((_d * _d) / _xp0) * _d) / _xp1 / 4;
                _prevD = _d;
                _d = (((400000_00 * _s) / 100 + 2 * _dP) * _d) / ((400000_00 / 100 - 1) * _d + 3 * _dP);
                if (within1(_d, _prevD)) {
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            _computed = _d;
        }
    }

    function _DGas1(uint _xp0, uint _xp1) external pure returns (uint _computed) {
        uint _s = _xp0 + _xp1;

        if (_s == 0) {
            _computed = 0;
        } else {
            uint _prevD;
            uint _d = _s;
            for (uint i; i < 256; ) {
                //uint _dP = (mulDiv(_d, _d, _xp0) * _d) / _xp1 / 4;
                uint _dP = mulDiv(mulDiv(_d, _d, _xp0), _d, _xp1) / 4;
                _prevD = _d;
                //_d = ((mulDiv(400000_00, _s, 100) + 2 * _dP) * _d) / ((400000_00 / 100 - 1) * _d + 3 * _dP);
                _d = mulDiv(
                    (mulDiv(400000_00, _s, 100) + 2 * _dP),
                    _d,
                    ((400000_00 / 100 - 1) * _d + 3 * _dP)
                );
                if (within1(_d, _prevD)) {
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            _computed = _d;
        }
    }

    function _DGas2(uint _xp0, uint _xp1) external pure returns (uint _computed) {
        uint _s = _xp0 + _xp1;

        if (_s == 0) {
            _computed = 0;
        } else {
            uint _prevD;
            uint _d = _s;
            for (uint i; i < 256; ) {
                //uint _dP = (mulDiv(_d, _d, _xp0) * _d) / _xp1 / 4;
                uint _dP = mulDiv(mulDiv(_d, _d, _xp0), _d, _xp1);
                _prevD = _d;
                //_d = ((mulDiv(400000_00, _s, 100) + 2 * _dP) * _d) / ((400000_00 / 100 - 1) * _d + 3 * _dP);
                /*
                _d = mulDiv(
                    (mulDiv(400000_00, _s, 100) + 2 * _dP),
                    _d,
                    ((400000_00 / 100 - 1) * _d + 3 * _dP)
                );
                */
                _d = mulDiv(
                    (mulDiv(400000_00, _s, 100) + mulDiv(2, _dP, 4)),
                    _d,
                    ((400000_00 / 100 - 1) * _d + mulDiv(3, _dP, 4))
                );
                if (within1(_d, _prevD)) {
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            _computed = _d;
        }
    }
}
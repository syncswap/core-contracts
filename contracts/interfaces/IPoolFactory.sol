// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity >=0.5.0;

interface IPoolFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function owner() external view returns (address);
    function pendingOwner() external view returns (address);

    function feeRecipient() external view returns (address);
    function protocolFee() external view returns (uint8);
    function defaultSwapFeeNonstable() external view returns (uint24);
    function defaultSwapFeeStable() external view returns (uint24);
    function customSwapFee(address) external view returns (bool exists, uint24 swapFee);

    function getPair(address tokenA, address tokenB, bool stable) external view returns (address pair);
    function isPair(address) external view returns (bool);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function swapFee(address pool) external view returns (uint24);

    function createPair(address tokenA, address tokenB, bool stable) external returns (address pair);

    function setPendingOwner(address pendingOwner) external;
    function acceptOwner() external;
    function setProtocolFee(uint8 protocolFee) external;
    function setDefaultSwapFeeNonstable(uint24 defaultSwapFeeNonstable) external;
    function setDefaultSwapFeeStable(uint24 defaultSwapFeeStable) external;
    function setCustomSwapFee(address pool, uint24 customSwapFee) external;
    function removeCustomSwapFee(address pool) external;
}
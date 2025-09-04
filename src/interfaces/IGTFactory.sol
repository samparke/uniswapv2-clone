// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IGTFactory {
    function feeAddress() external view returns (address);

    function feeSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address);

    function allPairs(uint256) external view returns (address);

    function createPool(address tokenA, address tokenB) external;

    function setFeeAddress(address newFeeAddress) external;

    function setFeeSetter(address newFeeSetter) external;
}

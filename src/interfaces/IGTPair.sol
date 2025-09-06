// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface IGTPair {
    function mint(address to) external returns (uint256);

    function burn(address to) external returns (uint256, uint256);

    function swap(uint256 amount0Out, uint256 amount1Out, address to) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function getReserves() external view returns (uint112, uint112, uint32);

    function initialise(address token0, address token1) external;
}

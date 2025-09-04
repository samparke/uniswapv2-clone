// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

interface ILP {
    function mint(address account, uint256 amount) external;

    function burn(address from, uint256 amount) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);
}

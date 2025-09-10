// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WETH is ERC20 {
    constructor() ERC20("Wrapped Ether", "WETH") {}

    mapping(address => uint256) public deposits;

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function deposit() external payable {
        deposits[msg.sender] += msg.value;
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        deposits[msg.sender] -= amount;
        _burn(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success);
    }
}

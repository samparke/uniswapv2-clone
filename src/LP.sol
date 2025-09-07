// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract LP is ERC20, ERC20Burnable {
    error LP__MustBeMoreThanZero();
    error LP__ZeroAddress();

    modifier moreThanZero(uint256 amount) virtual {
        if (amount == 0) {
            revert LP__MustBeMoreThanZero();
        }
        _;
    }

    constructor() ERC20("LP Token", "LP") {}

    function mint(address account, uint256 amount) external moreThanZero(amount) {
        _mint(account, amount);
    }

    function burn(address from, uint256 amount) external moreThanZero(amount) {
        _burn(from, amount);
    }
}

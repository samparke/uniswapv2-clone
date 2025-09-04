// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract GTToken is ERC20, Ownable, ERC20Burnable {
    error GTToken__MustBeMoreThanZero();
    error GTToken__ZeroAddress();

    address pool;

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert GTToken__MustBeMoreThanZero();
        }
        _;
    }

    constructor(address _pool) ERC20("GT Token", "GT") Ownable(_pool) {
        pool = _pool;
    }

    function mint(address account, uint256 amount) external moreThanZero(amount) onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external moreThanZero(amount) onlyOwner {
        _burn(account, amount);
    }
}

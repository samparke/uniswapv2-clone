// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {GTPool} from "../../src/GTPool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract GTPoolTest is Test {
    GTPool pool;
    ERC20Mock weth;
    ERC20Mock usdc;
    address feeAddress;
    uint256 public constant WETH_MINT_AMOUNT = 10 ether; // 10 WETH (18 decimals)
    uint256 public constant USDC_MINT_AMOUNT = 20_000 ether; // 20,000 USDC (18 decimals)
    // Price of ETH is $2000. 20,000 / 10 = 2,000

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        pool = new GTPool(address(weth), address(usdc), feeAddress);

        // change to someone depositing liquidity
        weth.mint(address(pool), WETH_MINT_AMOUNT);
        usdc.mint(address(pool), USDC_MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                              GET RESERVES
    //////////////////////////////////////////////////////////////*/
}

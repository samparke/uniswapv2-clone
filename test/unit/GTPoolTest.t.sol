// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {GTPool} from "../../src/GTPool.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract GTPoolTest is Test {
    GTPool pool;
    ERC20Mock weth;
    ERC20Mock usdc;
    address feeAddress;
    address firstLiquidityProvider = makeAddr("firstLiquidityProvider");
    address secondLiquidityProvider = makeAddr("secondLiquidityProvider");
    address thirdLiquidityProvider = makeAddr("thirdLiquidityProvider");

    uint256 public constant FIRST_DEPOSIT_WET_AMOUNT = 10 ether; // 10 WETH (18 decimals)
    uint256 public constant FIRST_DEPOSIT_USDC_AMOUNT = 20_000 ether; // 20,000 USDC (18 decimals)
    // Price of ETH is $2000. 20,000 / 10 = 2,000
    uint256 public constant DEPOSIT_WET_AMOUNT = 1 ether;
    uint256 public constant DEPOSIT_USDC_AMOUNT = 2_000 ether;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        pool = new GTPool(address(weth), address(usdc), feeAddress);

        weth.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_WET_AMOUNT);
        usdc.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_USDC_AMOUNT);

        weth.mint(address(secondLiquidityProvider), DEPOSIT_WET_AMOUNT);
        usdc.mint(address(secondLiquidityProvider), DEPOSIT_USDC_AMOUNT);

        weth.mint(address(thirdLiquidityProvider), DEPOSIT_WET_AMOUNT);
        usdc.mint(address(thirdLiquidityProvider), DEPOSIT_USDC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                              GET RESERVES
    //////////////////////////////////////////////////////////////*/

    function test_InitialReservesAndLastUpdatedAreZero() public view {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
        assertEq(blockTimestampLast, 0);
    }

    function test_ReserveAfterFirstLiquidityDeposit() public {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WET_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        (uint112 reserve0, uint112 reserve1, uint32 blockTimeStampLast) = pool.getReserves();
        assertEq(reserve0, FIRST_DEPOSIT_WET_AMOUNT);
        assertEq(reserve1, FIRST_DEPOSIT_USDC_AMOUNT);
        assertEq(blockTimeStampLast, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT LP
    //////////////////////////////////////////////////////////////*/

    function test_FirstLiquidityDeposit() public {
        assertEq(IERC20(weth).balanceOf(address(pool)), 0);
        assertEq(IERC20(usdc).balanceOf(address(pool)), 0);
        assertEq(pool.totalSupply(), 0);

        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WET_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        uint256 expectedLiquidityTokens =
            Math.sqrt(FIRST_DEPOSIT_WET_AMOUNT * FIRST_DEPOSIT_USDC_AMOUNT) - MINIMUM_LIQUIDITY;
        uint256 actualLiquidityTokens = pool.balanceOf(address(firstLiquidityProvider));

        assertEq(actualLiquidityTokens, expectedLiquidityTokens);
        assertEq(pool.totalSupply(), actualLiquidityTokens + MINIMUM_LIQUIDITY);
    }

    function test_NumerousLiquidityDeposits() public {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WET_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        IERC20(weth).transfer(address(pool), DEPOSIT_WET_AMOUNT);
        IERC20(usdc).transfer(address(pool), DEPOSIT_USDC_AMOUNT);
        pool.mint(secondLiquidityProvider);
        vm.stopPrank();

        (uint112 reserve0SecondDepositor, uint112 reserve1SecondDepositor,) = pool.getReserves();
        uint256 totalSupplySecondDepositor = pool.totalSupply();

        vm.startPrank(thirdLiquidityProvider);
        IERC20(weth).transfer(address(pool), DEPOSIT_WET_AMOUNT);
        IERC20(usdc).transfer(address(pool), DEPOSIT_USDC_AMOUNT);
        pool.mint(thirdLiquidityProvider);
        vm.stopPrank();

        (uint112 reserve0ThirdDepositor, uint112 reserve1ThirdDepositor,) = pool.getReserves();
        uint256 totalSupplyThirdDepositor = pool.totalSupply();

        uint256 expectedFirstLiquidityTokens =
            Math.sqrt(FIRST_DEPOSIT_WET_AMOUNT * FIRST_DEPOSIT_USDC_AMOUNT) - MINIMUM_LIQUIDITY;
        uint256 actualFirstLiquidityTokens = pool.balanceOf(address(firstLiquidityProvider));

        uint256 expectedSecondLiquidityTokens = Math.min(
            (DEPOSIT_WET_AMOUNT * totalSupplySecondDepositor) / reserve0SecondDepositor,
            (DEPOSIT_USDC_AMOUNT * totalSupplySecondDepositor) / reserve1SecondDepositor
        );
        uint256 actualSecondLiquidityTokens = pool.balanceOf(secondLiquidityProvider);

        uint256 expectedThirdLiquidityTokens = Math.min(
            (DEPOSIT_WET_AMOUNT * totalSupplyThirdDepositor) / reserve0ThirdDepositor,
            (DEPOSIT_USDC_AMOUNT * totalSupplyThirdDepositor) / reserve1ThirdDepositor
        );
        uint256 actualThirdLiquidityTokens = pool.balanceOf(thirdLiquidityProvider);

        assertEq(expectedFirstLiquidityTokens, actualFirstLiquidityTokens);
        console.log("First depositor LP tokens", actualFirstLiquidityTokens / PRECISION);
        assertEq(expectedSecondLiquidityTokens, actualSecondLiquidityTokens);
        console.log("Second depositor LP tokens", actualSecondLiquidityTokens / PRECISION);
        assertEq(expectedThirdLiquidityTokens, actualThirdLiquidityTokens);
        console.log("Third depositor LP tokens", actualThirdLiquidityTokens / PRECISION);
    }
}

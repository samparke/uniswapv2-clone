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

    uint256 public constant FIRST_DEPOSIT_WETH_AMOUNT = 10 ether; // 10 WETH (18 decimals)
    uint256 public constant FIRST_DEPOSIT_USDC_AMOUNT = 20_000 ether; // 20,000 USDC (18 decimals)
    // Price of ETH is $2000. 20,000 / 10 = 2,000
    uint256 public constant DEPOSIT_WETH_AMOUNT = 5 ether;
    uint256 public constant DEPOSIT_USDC_AMOUNT = 10_000 ether;

    uint256 public constant BURN_LP_AMOUNT = 1 ether;
    uint256 public constant WETH_RESERVE_INCREASE = 10 ether;
    uint256 public constant USDC_RESERVE_INCREASE = 20_000 ether;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        pool = new GTPool(address(weth), address(usdc), feeAddress);

        weth.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_USDC_AMOUNT);

        weth.mint(address(secondLiquidityProvider), DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(secondLiquidityProvider), DEPOSIT_USDC_AMOUNT);

        weth.mint(address(thirdLiquidityProvider), DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(thirdLiquidityProvider), DEPOSIT_USDC_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyFirstDepositLiquidityAndMintLP() {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();
        _;
    }

    modifier allDepositLiquidityAndMintLP() {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        IERC20(weth).transfer(address(pool), DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), DEPOSIT_USDC_AMOUNT);
        pool.mint(secondLiquidityProvider);
        vm.stopPrank();

        vm.startPrank(thirdLiquidityProvider);
        IERC20(weth).transfer(address(pool), DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), DEPOSIT_USDC_AMOUNT);
        pool.mint(thirdLiquidityProvider);
        vm.stopPrank();
        _;
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
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        (uint112 reserve0, uint112 reserve1, uint32 blockTimeStampLast) = pool.getReserves();
        assertEq(reserve0, FIRST_DEPOSIT_WETH_AMOUNT);
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
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        uint256 expectedLiquidityTokens =
            Math.sqrt(FIRST_DEPOSIT_WETH_AMOUNT * FIRST_DEPOSIT_USDC_AMOUNT) - MINIMUM_LIQUIDITY;
        uint256 actualLiquidityTokens = pool.balanceOf(address(firstLiquidityProvider));

        assertEq(actualLiquidityTokens, expectedLiquidityTokens);
        assertEq(pool.totalSupply(), actualLiquidityTokens + MINIMUM_LIQUIDITY);
    }

    function test_NumerousLiquidityDeposits() public {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        IERC20(weth).transfer(address(pool), DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), DEPOSIT_USDC_AMOUNT);
        pool.mint(secondLiquidityProvider);
        vm.stopPrank();

        (uint112 reserve0SecondDepositor, uint112 reserve1SecondDepositor,) = pool.getReserves();
        uint256 totalSupplySecondDepositor = pool.totalSupply();

        vm.startPrank(thirdLiquidityProvider);
        IERC20(weth).transfer(address(pool), DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), DEPOSIT_USDC_AMOUNT);
        pool.mint(thirdLiquidityProvider);
        vm.stopPrank();

        (uint112 reserve0ThirdDepositor, uint112 reserve1ThirdDepositor,) = pool.getReserves();
        uint256 totalSupplyThirdDepositor = pool.totalSupply();

        uint256 expectedFirstLiquidityTokens =
            Math.sqrt(FIRST_DEPOSIT_WETH_AMOUNT * FIRST_DEPOSIT_USDC_AMOUNT) - MINIMUM_LIQUIDITY;
        uint256 actualFirstLiquidityTokens = pool.balanceOf(address(firstLiquidityProvider));

        uint256 expectedSecondLiquidityTokens = Math.min(
            (DEPOSIT_WETH_AMOUNT * totalSupplySecondDepositor) / reserve0SecondDepositor,
            (DEPOSIT_USDC_AMOUNT * totalSupplySecondDepositor) / reserve1SecondDepositor
        );
        uint256 actualSecondLiquidityTokens = pool.balanceOf(secondLiquidityProvider);

        uint256 expectedThirdLiquidityTokens = Math.min(
            (DEPOSIT_WETH_AMOUNT * totalSupplyThirdDepositor) / reserve0ThirdDepositor,
            (DEPOSIT_USDC_AMOUNT * totalSupplyThirdDepositor) / reserve1ThirdDepositor
        );
        uint256 actualThirdLiquidityTokens = pool.balanceOf(thirdLiquidityProvider);

        assertEq(expectedFirstLiquidityTokens, actualFirstLiquidityTokens);
        console.log("First depositor LP tokens", actualFirstLiquidityTokens / PRECISION);
        assertEq(expectedSecondLiquidityTokens, actualSecondLiquidityTokens);
        console.log("Second depositor LP tokens", actualSecondLiquidityTokens / PRECISION);
        assertEq(expectedThirdLiquidityTokens, actualThirdLiquidityTokens);
        console.log("Third depositor LP tokens", actualThirdLiquidityTokens / PRECISION);
        console.log("Total LP tokens in supply", pool.totalSupply() / PRECISION);
    }

    /*//////////////////////////////////////////////////////////////
                                BURN LP
    //////////////////////////////////////////////////////////////*/

    function test_BurnAllFirstDepositorLPTokensNoYield() public {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        uint256 wethBalanceBefore = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(firstLiquidityProvider);

        assertEq(wethBalanceBefore, 0);
        assertEq(usdcBalanceBefore, 0);

        vm.startPrank(firstLiquidityProvider);
        IERC20(pool).transfer(address(pool), pool.balanceOf(firstLiquidityProvider));
        pool.burn(firstLiquidityProvider);
        vm.stopPrank();

        uint256 wethBalanceAfter = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(firstLiquidityProvider);

        // Because a small amount of the users deposit was minted to the dead address, they won't get 100% of the deposit back.
        assertApproxEqAbs(wethBalanceAfter, FIRST_DEPOSIT_WETH_AMOUNT, 1e6);
        assertApproxEqAbs(usdcBalanceAfter, FIRST_DEPOSIT_USDC_AMOUNT, 1e6);
    }

    function test_BurnHalfFirstDepositorLPTokensNoYield() public {
        vm.startPrank(firstLiquidityProvider);
        IERC20(weth).transfer(address(pool), FIRST_DEPOSIT_WETH_AMOUNT);
        IERC20(usdc).transfer(address(pool), FIRST_DEPOSIT_USDC_AMOUNT);
        pool.mint(firstLiquidityProvider);
        vm.stopPrank();

        vm.startPrank(firstLiquidityProvider);
        IERC20(pool).transfer(address(pool), (pool.balanceOf(firstLiquidityProvider)) / 2);
        pool.burn(firstLiquidityProvider);
        vm.stopPrank();

        uint256 wethBalanceAfter = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(firstLiquidityProvider);

        // Because a small amount of the users deposit was minted to the dead address, they won't get 100% of the deposit back.
        assertApproxEqAbs(wethBalanceAfter, FIRST_DEPOSIT_WETH_AMOUNT / 2, 1e6);
        assertApproxEqAbs(usdcBalanceAfter, FIRST_DEPOSIT_USDC_AMOUNT / 2, 1e6);
    }

    /**
     * @notice After the reserves have accumulated 10 ether and 20,000 usdc from fees (a lot), these are the expected amounts earned for each depositor.
     *
     * Pool balances:
     * WETH = 30 ether
     * USDC = 60,000
     *
     * First depositor:
     * - Deposited 10 ether and 20,000 USDC
     * - Owns 50% of the pool
     *
     * Second and third depositors:
     * - Each deposited 5 ether and 10,000 USDC
     * - Each 25% of the pool
     *
     * After burning LP tokens:
     * First depositor: (50% of 30 ether and 60,000) = 15 ether and 30,000 USDC
     * Second and third depositors: (25% of 30 ether and 60,000) = 7.5 ether and 15,000 UDSC
     */
    function test_BurnAllDepositorsAfterYieldEarned() public allDepositLiquidityAndMintLP {
        weth.mint(address(pool), WETH_RESERVE_INCREASE);
        usdc.mint(address(pool), USDC_RESERVE_INCREASE);

        vm.startPrank(firstLiquidityProvider);
        uint256 lpSupplyBeforeBurn = pool.totalSupply();
        IERC20(pool).transfer(address(pool), pool.balanceOf(firstLiquidityProvider));
        uint256 firstLiquidity = pool.balanceOf(address(pool));
        uint256 balance0 = IERC20(weth).balanceOf(address(pool));
        uint256 balance1 = IERC20(usdc).balanceOf(address(pool));
        pool.burn(firstLiquidityProvider);
        vm.stopPrank();

        uint256 expectedWethReturn = (firstLiquidity * balance0) / lpSupplyBeforeBurn;
        uint256 expectedUsdcReturn = (firstLiquidity * balance1) / lpSupplyBeforeBurn;

        assertApproxEqAbs(expectedWethReturn, IERC20(weth).balanceOf(firstLiquidityProvider), 1e6);
        assertApproxEqAbs(expectedUsdcReturn, IERC20(usdc).balanceOf(firstLiquidityProvider), 1e6);

        vm.startPrank(secondLiquidityProvider);
        lpSupplyBeforeBurn = pool.totalSupply();
        IERC20(pool).transfer(address(pool), pool.balanceOf(secondLiquidityProvider));
        uint256 secondLiquidity = pool.balanceOf(address(pool));
        balance0 = IERC20(weth).balanceOf(address(pool));
        balance1 = IERC20(usdc).balanceOf(address(pool));
        pool.burn(secondLiquidityProvider);
        vm.stopPrank();

        expectedWethReturn = (secondLiquidity * balance0) / lpSupplyBeforeBurn;
        expectedUsdcReturn = (secondLiquidity * balance1) / lpSupplyBeforeBurn;

        assertEq(expectedWethReturn, IERC20(weth).balanceOf(secondLiquidityProvider));
        assertEq(expectedUsdcReturn, IERC20(usdc).balanceOf(secondLiquidityProvider));

        vm.startPrank(thirdLiquidityProvider);
        lpSupplyBeforeBurn = pool.totalSupply();
        IERC20(pool).transfer(address(pool), pool.balanceOf(thirdLiquidityProvider));
        uint256 thirdLiquidity = pool.balanceOf(address(pool));
        balance0 = IERC20(weth).balanceOf(address(pool));
        balance1 = IERC20(usdc).balanceOf(address(pool));
        pool.burn(thirdLiquidityProvider);
        vm.stopPrank();

        expectedWethReturn = (thirdLiquidity * balance0) / lpSupplyBeforeBurn;
        expectedUsdcReturn = (thirdLiquidity * balance1) / lpSupplyBeforeBurn;

        assertEq(expectedWethReturn, IERC20(weth).balanceOf(thirdLiquidityProvider));
        assertEq(expectedUsdcReturn, IERC20(usdc).balanceOf(thirdLiquidityProvider));
    }
}

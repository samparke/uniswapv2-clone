// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console, console2} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGTPair} from "../../src/interfaces/IGTPair.sol";
import {GTRouter} from "../../src/GTRouter.sol";
import {GTLibrary} from "../../src/libraries/GTLibrary.sol";

contract GTPairTest is Test {
    address pair;
    GTFactory factory;
    GTRouter router;
    ERC20Mock weth;
    ERC20Mock usdc;
    address feeAddress = makeAddr("feeAddress");
    address firstLiquidityProvider = makeAddr("firstLiquidityProvider");
    address secondLiquidityProvider = makeAddr("secondLiquidityProvider");
    address thirdLiquidityProvider = makeAddr("thirdLiquidityProvider");

    uint256 public constant BURN_LP_AMOUNT = 1 ether;

    uint256 public constant WETH_RESERVE_INCREASE = 10 ether;
    uint256 public constant USDC_RESERVE_INCREASE = 20_000 ether;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    uint256 public deadline = block.timestamp + 10 minutes;

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        factory = new GTFactory(feeAddress, feeAddress);
        router = new GTRouter(address(factory));
        vm.prank(address(factory));
        pair = factory.createPair(address(weth), address(usdc));

        vm.startPrank(firstLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(pair).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(pair).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(thirdLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(pair).approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              GET RESERVES
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CorrectOrderForTokensInPair(address tokenA, address tokenB) public {
        vm.assume(tokenA != address(0));
        vm.assume(tokenB != address(0));
        vm.assume(tokenA != tokenB);

        address newPair;
        vm.prank(address(factory));
        newPair = factory.createPair(tokenA, tokenB);
        (address token0, address token1) = (IGTPair(newPair).getTokens());
        (address sortedToken0, address sortedToken1) = GTLibrary.sortTokens(tokenA, tokenB);
        assertEq(token0, sortedToken0);
        assertEq(token1, sortedToken1);
    }

    function testFuzz_ReserveAfterFirstLiquidityDeposit(uint256 wethAmount, uint256 usdcAmount) public {
        wethAmount = bound(wethAmount, 1e6, type(uint96).max);
        usdcAmount = bound(usdcAmount, 1e6, type(uint96).max);
        weth.mint(firstLiquidityProvider, wethAmount);
        usdc.mint(firstLiquidityProvider, usdcAmount);

        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            wethAmount,
            usdcAmount,
            wethAmount,
            usdcAmount,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();
        (uint112 reserve0, uint112 reserve1, uint32 blockTimeStampLast) = IGTPair(pair).getReserves();
        if (weth < usdc) {
            assertEq(reserve0, wethAmount);
            assertEq(reserve1, usdcAmount);
        }
        assertEq(reserve0, usdcAmount);
        assertEq(reserve1, wethAmount);
        assertEq(blockTimeStampLast, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT LP
    //////////////////////////////////////////////////////////////*/

    function testFuzz_FirstLiquidityDeposit(uint256 wethAmount, uint256 usdcAmount) public {
        wethAmount = bound(wethAmount, 1e6, type(uint96).max);
        usdcAmount = bound(usdcAmount, 1e6, type(uint96).max);
        weth.mint(firstLiquidityProvider, wethAmount);
        usdc.mint(firstLiquidityProvider, usdcAmount);

        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            wethAmount,
            usdcAmount,
            wethAmount,
            usdcAmount,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 expectedLiquidityTokens = Math.sqrt(wethAmount * usdcAmount) - MINIMUM_LIQUIDITY;
        uint256 actualLiquidityTokens = IGTPair(pair).balanceOf(address(firstLiquidityProvider));

        assertEq(actualLiquidityTokens, expectedLiquidityTokens);
        assertEq(IGTPair(pair).totalSupply(), actualLiquidityTokens + MINIMUM_LIQUIDITY);
    }

    function testFuzz_NumerousLiquidityDeposits(
        uint256 firstWethAmount,
        uint256 firstUsdcAmount,
        uint256 secondWethAmount,
        uint256 secondUsdcAmount
    ) public {
        firstWethAmount = bound(firstWethAmount, 1e6, type(uint96).max);
        firstUsdcAmount = bound(firstUsdcAmount, 1e6, type(uint96).max);
        secondWethAmount = bound(firstWethAmount, 1e6, type(uint96).max);
        secondUsdcAmount = bound(firstUsdcAmount, 1e6, type(uint96).max);
        weth.mint(firstLiquidityProvider, firstWethAmount);
        usdc.mint(firstLiquidityProvider, firstUsdcAmount);
        weth.mint(secondLiquidityProvider, secondWethAmount);
        usdc.mint(secondLiquidityProvider, secondUsdcAmount);
        weth.mint(thirdLiquidityProvider, secondWethAmount);
        usdc.mint(thirdLiquidityProvider, secondUsdcAmount);

        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            firstWethAmount,
            firstUsdcAmount,
            firstWethAmount,
            firstUsdcAmount,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            secondWethAmount,
            secondUsdcAmount,
            secondWethAmount,
            secondUsdcAmount,
            secondLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        (uint112 reserve0SecondDepositor, uint112 reserve1SecondDepositor,) = IGTPair(pair).getReserves();
        uint256 totalSupplySecondDepositor = IGTPair(pair).totalSupply();

        vm.startPrank(thirdLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            secondWethAmount,
            secondUsdcAmount,
            secondWethAmount,
            secondUsdcAmount,
            thirdLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        (uint112 reserve0ThirdDepositor, uint112 reserve1ThirdDepositor,) = IGTPair(pair).getReserves();
        uint256 totalSupplyThirdDepositor = IGTPair(pair).totalSupply();

        uint256 expectedFirstLiquidityTokens = Math.sqrt(firstUsdcAmount * firstWethAmount) - MINIMUM_LIQUIDITY;
        uint256 actualFirstLiquidityTokens = IGTPair(pair).balanceOf(address(firstLiquidityProvider));

        uint256 expectedSecondLiquidityTokens = Math.min(
            (secondUsdcAmount * totalSupplySecondDepositor) / reserve0SecondDepositor,
            (secondWethAmount * totalSupplySecondDepositor) / reserve1SecondDepositor
        );
        uint256 actualSecondLiquidityTokens = IGTPair(pair).balanceOf(secondLiquidityProvider);

        uint256 expectedThirdLiquidityTokens = Math.min(
            (secondUsdcAmount * totalSupplyThirdDepositor) / reserve0ThirdDepositor,
            (secondWethAmount * totalSupplyThirdDepositor) / reserve1ThirdDepositor
        );
        uint256 actualThirdLiquidityTokens = IGTPair(pair).balanceOf(thirdLiquidityProvider);

        assertEq(expectedFirstLiquidityTokens, actualFirstLiquidityTokens);
        console.log("First depositor LP tokens", actualFirstLiquidityTokens / PRECISION);
        assertEq(expectedSecondLiquidityTokens, actualSecondLiquidityTokens);
        console.log("Second depositor LP tokens", actualSecondLiquidityTokens / PRECISION);
        assertEq(expectedThirdLiquidityTokens, actualThirdLiquidityTokens);
        console.log("Third depositor LP tokens", actualThirdLiquidityTokens / PRECISION);
        console.log("Total LP tokens in supply", IGTPair(pair).totalSupply() / PRECISION);
    }

    /*//////////////////////////////////////////////////////////////
                                BURN LP
    //////////////////////////////////////////////////////////////*/

    function testFuzz_BurnAllFirstDepositorLPTokensNoYield(uint256 wethAmount, uint256 usdcAmount) public {
        // Bounded to
        wethAmount = bound(wethAmount, 1e6, type(uint64).max);
        usdcAmount = bound(usdcAmount, 1e6, type(uint64).max);
        weth.mint(firstLiquidityProvider, wethAmount);
        usdc.mint(firstLiquidityProvider, usdcAmount);

        uint256 wethBalanceStart = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceStart = IERC20(usdc).balanceOf(firstLiquidityProvider);

        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            wethAmount,
            usdcAmount,
            wethAmount,
            usdcAmount,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 wethBalanceBefore = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(firstLiquidityProvider);

        assertEq(wethBalanceBefore, 0);
        assertEq(usdcBalanceBefore, 0);

        vm.startPrank(firstLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            IERC20(pair).balanceOf(firstLiquidityProvider),
            0,
            0,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 wethBalanceAfter = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(firstLiquidityProvider);

        console2.log(wethBalanceStart);
        console2.log(usdcBalanceStart);
        console2.log(wethBalanceAfter);
        console2.log(usdcBalanceAfter);

        // Because a small amount of the users deposit was minted to the dead address, they won't get 100% of the deposit back.
        // 0.00000001 ether
        assertApproxEqAbs(wethBalanceAfter, wethAmount, 1e10);
        assertApproxEqAbs(usdcBalanceAfter, usdcAmount, 1e10);
    }

    function testFuzz_BurnHalfFirstDepositorLPTokensNoYield(uint256 wethAmount, uint256 usdcAmount) public {
        wethAmount = bound(wethAmount, 1e6, type(uint64).max);
        usdcAmount = bound(usdcAmount, 1e6, type(uint64).max);
        weth.mint(firstLiquidityProvider, wethAmount);
        usdc.mint(firstLiquidityProvider, usdcAmount);

        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            wethAmount,
            usdcAmount,
            wethAmount,
            usdcAmount,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(firstLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            IERC20(pair).balanceOf(firstLiquidityProvider) / 2,
            0,
            0,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 wethBalanceAfter = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(firstLiquidityProvider);

        // Because a small amount of the users deposit was minted to the dead address, they won't get 100% of the deposit back.
        assertApproxEqAbs(wethBalanceAfter, wethAmount / 2, 1e10);
        assertApproxEqAbs(usdcBalanceAfter, usdcAmount / 2, 1e10);
    }

    //     /*//////////////////////////////////////////////////////////////
    //                                   SWAP
    //     //////////////////////////////////////////////////////////////*/
}

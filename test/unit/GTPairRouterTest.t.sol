// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test, console, console2} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {WETH} from "../../test/mocks/WETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IGTPair} from "../../src/interfaces/IGTPair.sol";
import {GTRouter} from "../../src/GTRouter.sol";
import {GTLibrary} from "../../src/libraries/GTLibrary.sol";

contract GTPairRouterTest is Test {
    address wethUsdcPair;
    address usdcDaiPair;
    GTFactory factory;
    GTRouter router;
    WETH weth;
    ERC20Mock usdc;
    ERC20Mock dai;
    address feeAddress = makeAddr("feeAddress");
    address firstLiquidityProvider = makeAddr("firstLiquidityProvider");
    address secondLiquidityProvider = makeAddr("secondLiquidityProvider");
    address thirdLiquidityProvider = makeAddr("thirdLiquidityProvider");
    address daiDepositor = makeAddr("daiDepositor");
    address swapper = makeAddr("swapper");

    uint256 public constant FIRST_DEPOSIT_WETH_AMOUNT = 10 ether; // 10 WETH (18 decimals)
    uint256 public constant FIRST_DEPOSIT_USDC_AMOUNT = 20_000 ether; // 20,000 USDC (18 decimals)
    // Price of ETH is $2000. 20,000 / 10 = 2,000
    uint256 public constant FIRST_MIN_ACCEPTED_WETH_DEPOSIT = 9 ether;
    uint256 public constant FIRST_MIN_ACCEPTED_USDC_DEPOSIT = 18_000 ether;

    uint256 public constant DEPOSIT_WETH_AMOUNT = 5 ether;
    uint256 public constant DEPOSIT_USDC_AMOUNT = 10_000 ether;
    uint256 public constant MIN_ACCEPTED_WETH_DEPOSIT = 4 ether;
    uint256 public constant MIN_ACCEPTED_USDC_DEPOSIT = 8_000 ether;

    uint256 public constant DEPOSIT_DAI_AMOUNT = 10 ether;

    uint256 public constant BURN_LP_AMOUNT = 1 ether;

    uint256 public constant WETH_RESERVE_INCREASE = 10 ether;
    uint256 public constant USDC_RESERVE_INCREASE = 20_000 ether;

    uint256 public constant SWAPPER_INITIAL_WETH = 1 ether;
    uint256 public constant SWAPPER_INITIAL_USDC = 2000 ether;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    uint256 public deadline = block.timestamp + 10 minutes;

    function setUp() public {
        weth = new WETH();
        usdc = new ERC20Mock();
        dai = new ERC20Mock();
        factory = new GTFactory(address(0), feeAddress);
        router = new GTRouter(address(factory), address(weth));
        vm.prank(address(factory));
        wethUsdcPair = factory.createPair(address(weth), address(usdc));
        vm.prank(address(factory));
        usdcDaiPair = factory.createPair(address(usdc), address(dai));

        weth.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_USDC_AMOUNT);
        dai.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_USDC_AMOUNT);

        weth.mint(address(secondLiquidityProvider), DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(secondLiquidityProvider), DEPOSIT_USDC_AMOUNT);

        weth.mint(address(thirdLiquidityProvider), DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(thirdLiquidityProvider), DEPOSIT_USDC_AMOUNT);

        weth.mint(address(swapper), SWAPPER_INITIAL_WETH);
        // usdc.mint(address(swapper), SWAPPER_INITIAL_USDC);

        dai.mint(address(daiDepositor), DEPOSIT_DAI_AMOUNT);
        usdc.mint(address(daiDepositor), DEPOSIT_DAI_AMOUNT);
        weth.mint(address(daiDepositor), 1 ether);

        vm.startPrank(firstLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(wethUsdcPair).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(wethUsdcPair).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(thirdLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(wethUsdcPair).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        dai.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(daiDepositor);
        dai.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        IERC20(usdcDaiPair).approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyFirstDepositLiquidityAndMintLP() {
        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();
        _;
    }

    modifier allDepositLiquidityAndMintLP() {
        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(secondLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            DEPOSIT_WETH_AMOUNT,
            DEPOSIT_USDC_AMOUNT,
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            secondLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(thirdLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            DEPOSIT_WETH_AMOUNT,
            DEPOSIT_USDC_AMOUNT,
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            thirdLiquidityProvider,
            deadline
        );
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              GET RESERVES
    //////////////////////////////////////////////////////////////*/

    function testCorrectOrderForTokensInPair() public view {
        (address token0, address token1) = (IGTPair(wethUsdcPair).getTokens());
        (address sortedToken0, address sortedToken1) = GTLibrary.sortTokens(address(weth), address(usdc));
        assertEq(token0, sortedToken0);
        assertEq(token1, sortedToken1);
    }

    function test_InitialReservesAndLastUpdatedAreZero() public view {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IGTPair(wethUsdcPair).getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);
        assertEq(blockTimestampLast, 0);
    }

    function test_ReserveAfterFirstLiquidityDeposit() public onlyFirstDepositLiquidityAndMintLP {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimeStampLast) = IGTPair(wethUsdcPair).getReserves();
        if (address(weth) < address(usdc)) {
            assertEq(reserve0, FIRST_DEPOSIT_WETH_AMOUNT);
            assertEq(reserve1, FIRST_DEPOSIT_USDC_AMOUNT);
        }
        assertEq(reserve0, FIRST_DEPOSIT_USDC_AMOUNT);
        assertEq(reserve1, FIRST_DEPOSIT_WETH_AMOUNT);
        assertEq(blockTimeStampLast, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                              MINT LP
    //////////////////////////////////////////////////////////////*/

    function test_FirstLiquidityDeposit() public {
        assertEq(IERC20(weth).balanceOf(address(wethUsdcPair)), 0);
        assertEq(IERC20(usdc).balanceOf(address(wethUsdcPair)), 0);
        assertEq(IGTPair(wethUsdcPair).totalSupply(), 0);

        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 expectedLiquidityTokens =
            Math.sqrt(FIRST_DEPOSIT_WETH_AMOUNT * FIRST_DEPOSIT_USDC_AMOUNT) - MINIMUM_LIQUIDITY;
        uint256 actualLiquidityTokens = IGTPair(wethUsdcPair).balanceOf(address(firstLiquidityProvider));

        assertEq(actualLiquidityTokens, expectedLiquidityTokens);
        assertEq(IGTPair(wethUsdcPair).totalSupply(), actualLiquidityTokens + MINIMUM_LIQUIDITY);
    }

    function test_NumerousLiquidityDeposits() public onlyFirstDepositLiquidityAndMintLP {
        vm.startPrank(secondLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            DEPOSIT_WETH_AMOUNT,
            DEPOSIT_USDC_AMOUNT,
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            secondLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        (uint112 reserve0SecondDepositor, uint112 reserve1SecondDepositor,) = IGTPair(wethUsdcPair).getReserves();
        uint256 totalSupplySecondDepositor = IGTPair(wethUsdcPair).totalSupply();

        vm.startPrank(thirdLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            DEPOSIT_WETH_AMOUNT,
            DEPOSIT_USDC_AMOUNT,
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            thirdLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        (uint112 reserve0ThirdDepositor, uint112 reserve1ThirdDepositor,) = IGTPair(wethUsdcPair).getReserves();
        uint256 totalSupplyThirdDepositor = IGTPair(wethUsdcPair).totalSupply();

        uint256 expectedFirstLiquidityTokens =
            Math.sqrt(FIRST_DEPOSIT_USDC_AMOUNT * FIRST_DEPOSIT_WETH_AMOUNT) - MINIMUM_LIQUIDITY;
        uint256 actualFirstLiquidityTokens = IGTPair(wethUsdcPair).balanceOf(address(firstLiquidityProvider));

        uint256 expectedSecondLiquidityTokens = Math.min(
            (DEPOSIT_USDC_AMOUNT * totalSupplySecondDepositor) / reserve0SecondDepositor,
            (DEPOSIT_WETH_AMOUNT * totalSupplySecondDepositor) / reserve1SecondDepositor
        );
        uint256 actualSecondLiquidityTokens = IGTPair(wethUsdcPair).balanceOf(secondLiquidityProvider);

        uint256 expectedThirdLiquidityTokens = Math.min(
            (DEPOSIT_USDC_AMOUNT * totalSupplyThirdDepositor) / reserve0ThirdDepositor,
            (DEPOSIT_WETH_AMOUNT * totalSupplyThirdDepositor) / reserve1ThirdDepositor
        );
        uint256 actualThirdLiquidityTokens = IGTPair(wethUsdcPair).balanceOf(thirdLiquidityProvider);

        assertEq(expectedFirstLiquidityTokens, actualFirstLiquidityTokens);
        console.log("First depositor LP tokens", actualFirstLiquidityTokens / PRECISION);
        assertEq(expectedSecondLiquidityTokens, actualSecondLiquidityTokens);
        console.log("Second depositor LP tokens", actualSecondLiquidityTokens / PRECISION);
        assertEq(expectedThirdLiquidityTokens, actualThirdLiquidityTokens);
        console.log("Third depositor LP tokens", actualThirdLiquidityTokens / PRECISION);
        console.log("Total LP tokens in supply", IGTPair(wethUsdcPair).totalSupply() / PRECISION);
    }

    function test_AddETHLiquidity() public {
        vm.deal(daiDepositor, 1 ether);
        vm.prank(daiDepositor);

        router.addLiquidityETH{value: 1 ether}(address(dai), 10 ether, 10 ether, 1 ether, daiDepositor, deadline);

        assertEq(daiDepositor.balance, 0);
        assertEq(weth.balanceOf(GTLibrary.pairFor(address(factory), address(weth), address(dai))), 1 ether);
        assertGt(IERC20(GTLibrary.pairFor(address(factory), address(weth), address(dai))).balanceOf(daiDepositor), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                BURN LP
    //////////////////////////////////////////////////////////////*/

    function test_BurnAllFirstDepositorLPTokensNoYield() public onlyFirstDepositLiquidityAndMintLP {
        uint256 wethBalanceBefore = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceBefore = IERC20(usdc).balanceOf(firstLiquidityProvider);

        assertEq(wethBalanceBefore, 0);
        assertEq(usdcBalanceBefore, 0);

        vm.startPrank(firstLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            IERC20(wethUsdcPair).balanceOf(firstLiquidityProvider),
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 wethBalanceAfter = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(firstLiquidityProvider);

        // Because a small amount of the users deposit was minted to the dead address, they won't get 100% of the deposit back.
        assertApproxEqAbs(wethBalanceAfter, FIRST_DEPOSIT_WETH_AMOUNT, 1e6);
        assertApproxEqAbs(usdcBalanceAfter, FIRST_DEPOSIT_USDC_AMOUNT, 1e6);
    }

    function test_BurnHalfFirstDepositorLPTokensNoYield() public onlyFirstDepositLiquidityAndMintLP {
        vm.startPrank(firstLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            (IERC20(wethUsdcPair).balanceOf(firstLiquidityProvider) / 2),
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        uint256 wethBalanceAfter = IERC20(weth).balanceOf(firstLiquidityProvider);
        uint256 usdcBalanceAfter = IERC20(usdc).balanceOf(firstLiquidityProvider);

        // Because a small amount of the users deposit was minted to the dead address, they won't get 100% of the deposit back.
        assertApproxEqAbs(wethBalanceAfter, FIRST_DEPOSIT_WETH_AMOUNT / 2, 1e6);
        assertApproxEqAbs(usdcBalanceAfter, FIRST_DEPOSIT_USDC_AMOUNT / 2, 1e6);
    }

    /**
     * @notice After the reserves have accumulated 10 ether and 20,000 usdc from fees, these are the expected amounts earned for each depositor.
     *
     * pair balances:
     * WETH = 30 ether
     * USDC = 60,000
     *
     * First depositor:
     * - Deposited 10 ether and 20,000 USDC
     * - Owns 50% of the pair
     *
     * Second and third depositors:
     * - Each deposited 5 ether and 10,000 USDC
     * - Each 25% of the pair
     *
     * After burning LP tokens:
     * First depositor: (50% of 30 ether and 60,000) = 15 ether and 30,000 USDC
     * Second and third depositors: (25% of 30 ether and 60,000) = 7.5 ether and 15,000 UDSC
     */
    function test_BurnAllDepositorsAfterYieldEarned() public allDepositLiquidityAndMintLP {
        weth.mint(address(wethUsdcPair), WETH_RESERVE_INCREASE);
        usdc.mint(address(wethUsdcPair), USDC_RESERVE_INCREASE);

        vm.startPrank(firstLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            IERC20(wethUsdcPair).balanceOf(firstLiquidityProvider),
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        // Due to mint of ghost shares, the amount back will not be the amount entered.
        assertApproxEqAbs(15 ether, IERC20(weth).balanceOf(firstLiquidityProvider), 1e6);
        console2.log(IERC20(weth).balanceOf(firstLiquidityProvider));
        assertApproxEqAbs(30_000 ether, IERC20(usdc).balanceOf(firstLiquidityProvider), 1e6);

        vm.startPrank(secondLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            IERC20(wethUsdcPair).balanceOf(secondLiquidityProvider),
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            secondLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        assertApproxEqAbs(7.5 ether, IERC20(weth).balanceOf(secondLiquidityProvider), 100);
        assertApproxEqAbs(15_000 ether, IERC20(usdc).balanceOf(secondLiquidityProvider), 100);

        vm.startPrank(thirdLiquidityProvider);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            IERC20(wethUsdcPair).balanceOf(thirdLiquidityProvider),
            MIN_ACCEPTED_WETH_DEPOSIT,
            MIN_ACCEPTED_USDC_DEPOSIT,
            thirdLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        // Due to Solidity division always rounding down, minting LP tokens can leave a few wei unaccounted for, meaning a small amount of dust will remain in the pool, and LP's won't get back the exact full amount provided.
        assertApproxEqAbs(7.5 ether, IERC20(weth).balanceOf(thirdLiquidityProvider), 100);
        assertApproxEqAbs(15_000 ether, IERC20(usdc).balanceOf(thirdLiquidityProvider), 100);
    }

    function test_removeLiquidityETH() public {
        vm.deal(daiDepositor, 1 ether);
        vm.prank(daiDepositor);
        router.addLiquidityETH{value: 1 ether}(address(dai), 10 ether, 10 ether, 1 ether, daiDepositor, deadline);
        assertEq(daiDepositor.balance, 0);
        vm.startPrank(daiDepositor);
        IERC20(GTLibrary.pairFor(address(factory), address(dai), address(weth))).approve(
            address(router), type(uint256).max
        );
        router.removeLiquidityETH(
            address(dai),
            IERC20(GTLibrary.pairFor(address(factory), address(dai), address(weth))).balanceOf(daiDepositor),
            // Because they were the first liquidity provider, they will not be able to retreive entire intial deposit.
            10 ether - 1e10,
            1 ether - 1e10,
            daiDepositor,
            deadline
        );
        vm.stopPrank();

        assertEq(IERC20(GTLibrary.pairFor(address(factory), address(dai), address(weth))).balanceOf(daiDepositor), 0);
        assertApproxEqAbs(daiDepositor.balance, 1 ether, 1e10);
        assertApproxEqAbs(IERC20(address(dai)).balanceOf(daiDepositor), 10 ether, 1e10);
    }

    /*//////////////////////////////////////////////////////////////
                                  SWAP
    //////////////////////////////////////////////////////////////*/

    function test_SwapExactTokensForTokens() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        uint256[] memory amounts = router.getAmountsOut(SWAPPER_INITIAL_WETH, path);
        uint256 expectedAmount = amounts[1];
        vm.prank(swapper);
        router.swapExactTokensForTokens(SWAPPER_INITIAL_WETH, SWAPPER_INITIAL_WETH, path, swapper, deadline);

        assertEq(IERC20(weth).balanceOf(address(swapper)), 0);
        assertEq(IERC20(usdc).balanceOf(address(swapper)), expectedAmount);
    }

    function testSwapMultipleTokens() public onlyFirstDepositLiquidityAndMintLP {
        vm.prank(daiDepositor);
        router.addLiquidity(
            address(usdc),
            address(dai),
            DEPOSIT_DAI_AMOUNT,
            DEPOSIT_DAI_AMOUNT,
            1 ether,
            1 ether,
            daiDepositor,
            deadline
        );
        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(usdc);
        path[2] = address(dai);

        uint256[] memory amounts = router.getAmountsOut(SWAPPER_INITIAL_WETH, path);
        uint256 expectedDai = amounts[2];

        vm.prank(swapper);
        router.swapExactTokensForTokens(SWAPPER_INITIAL_WETH, SWAPPER_INITIAL_WETH, path, swapper, deadline);

        assertEq(IERC20(address(dai)).balanceOf(swapper), expectedDai);
    }

    function test_SwapTokensForExactTokens() public onlyFirstDepositLiquidityAndMintLP {
        // Using dai depositor to create new pool
        vm.prank(daiDepositor);
        router.addLiquidity(
            address(usdc),
            address(dai),
            DEPOSIT_DAI_AMOUNT,
            DEPOSIT_DAI_AMOUNT,
            1 ether,
            1 ether,
            daiDepositor,
            deadline
        );
        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(usdc);
        path[2] = address(dai);

        uint256[] memory amounts = router.getAmountsOut(SWAPPER_INITIAL_WETH, path);
        uint256 expectedDai = amounts[2];

        vm.prank(swapper);
        router.swapTokensForExactTokens(expectedDai, SWAPPER_INITIAL_WETH, path, swapper, deadline);

        assertEq(IERC20(address(dai)).balanceOf(swapper), expectedDai);
    }

    function test_SwapExactEthForTokens() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        vm.deal(swapper, 1 ether);
        vm.prank(swapper);
        router.swapExactETHForTokens{value: 1 ether}(1 ether, path, swapper, deadline);
        assertEq(swapper.balance, 0);
        // 1 ether from this swap plus inital 10 ether
        assertEq(IERC20(weth).balanceOf(GTLibrary.pairFor(address(factory), address(weth), address(usdc))), 11 ether);
        assertGt(IERC20(usdc).balanceOf(swapper), 0);
    }

    function test_RevertSwapExactEthForTokensInvalidPath() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        vm.deal(swapper, 1 ether);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__InvalidPath.selector);
        router.swapExactETHForTokens{value: 1 ether}(1 ether, path, swapper, deadline);
    }

    // function test_RevertSwapExactEthForTokensInsufficientOutput() public onlyFirstDepositLiquidityAndMintLP {
    //     address[] memory path = new address[](2);
    //     path[0] = address(weth);
    //     path[1] = address(usdc);
    //     vm.deal(swapper, 1 ether);
    //     vm.prank(swapper);
    //     vm.expectRevert(GTRouter.GTRouter__InsufficientOutputAmount.selector);
    //     router.swapExactETHForTokens{value: 1 ether}(100 ether, path, swapper, deadline);
    // }

    function test_SwapTokensForExactEth() public onlyFirstDepositLiquidityAndMintLP {
        vm.deal(address(router), 10 ether);
        vm.prank(address(router));
        weth.deposit{value: 1 ether}();
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        usdc.mint(swapper, 3000 ether);
        uint256 initialSwapperUsdc = IERC20(address(usdc)).balanceOf(swapper);
        assertEq(initialSwapperUsdc, 3000 ether);
        vm.prank(swapper);
        router.swapTokensForExactETH(1 ether, 2300 ether, path, swapper, deadline);
        assertEq(
            IERC20(address(usdc)).balanceOf(swapper),
            initialSwapperUsdc
                - (IERC20(usdc).balanceOf(GTLibrary.pairFor(address(factory), address(weth), address(usdc))) - 20_000 ether)
        );

        assertEq(swapper.balance, 1 ether);
    }

    function test_RevertSwapTokensForExactEthInvalidPath() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__InvalidPath.selector);
        router.swapTokensForExactETH(1 ether, 2300 ether, path, swapper, deadline);
    }

    function test_RevertSwapTokensForExactEthExcessiveInput() public onlyFirstDepositLiquidityAndMintLP {
        vm.deal(address(router), 10 ether);
        vm.prank(address(router));
        weth.deposit{value: 1 ether}();
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        usdc.mint(swapper, 3000 ether);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__ExcessiveInputAmount.selector);
        router.swapTokensForExactETH(1 ether, 2000 ether, path, swapper, deadline);
    }

    function test_SwapExactTokensForETH() public onlyFirstDepositLiquidityAndMintLP {
        vm.deal(address(router), 10 ether);
        vm.prank(address(router));
        weth.deposit{value: 1 ether}();
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        usdc.mint(swapper, 2000 ether);
        vm.prank(swapper);
        router.swapExactTokensForETH(2000 ether, 0.8 ether, path, swapper, deadline);
        assertGt(swapper.balance, 0.8 ether);
    }

    function test_RevertSwapExactTokensForETHInvalidPath() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__InvalidPath.selector);
        router.swapExactTokensForETH(2000 ether, 0.8 ether, path, swapper, deadline);
    }

    function test_RevertSwapExactTokensForEthInsufficientOut() public onlyFirstDepositLiquidityAndMintLP {
        vm.deal(address(router), 10 ether);
        vm.prank(address(router));
        weth.deposit{value: 1 ether}();
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        usdc.mint(swapper, 2000 ether);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__InsufficientOutputAmount.selector);
        router.swapExactTokensForETH(2000 ether, 1 ether, path, swapper, deadline);
    }

    function test_SwapETHForExactTokens() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        vm.deal(swapper, 1 ether);
        vm.prank(swapper);
        router.swapETHForExactTokens{value: 1 ether}(1500 ether, path, swapper, deadline);
        assertEq(IERC20(usdc).balanceOf(swapper), 1500 ether);
        // As there will be remaining ETH unused in the swap (we overpaid), we should expect a refund.
        assertGt(swapper.balance, 0);
    }

    function test_RevertSwapETHForExactTokensInvalidPath() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);
        vm.deal(swapper, 1 ether);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__InvalidPath.selector);
        router.swapETHForExactTokens{value: 1 ether}(1500 ether, path, swapper, deadline);
    }

    function test_RevertSwapETHForExactTokensExcessiveInputAmount() public onlyFirstDepositLiquidityAndMintLP {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(usdc);
        vm.deal(swapper, 1 ether);
        vm.prank(swapper);
        vm.expectRevert(GTRouter.GTRouter__ExcessiveInputAmount.selector);
        // 1 ether ≠ 2000 USDC due to pool rebalancing
        router.swapETHForExactTokens{value: 1 ether}(2000 ether, path, swapper, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                                  SYNC
    //////////////////////////////////////////////////////////////*/

    function test_syncSuccessful() public {
        (uint112 initialReserve0, uint112 initialReserve1,) = IGTPair(address(wethUsdcPair)).getReserves();
        assertEq(initialReserve0, 0);
        assertEq(initialReserve1, 0);
        weth.mint(address(wethUsdcPair), 1 ether);
        usdc.mint(address(wethUsdcPair), 1 ether);

        IGTPair(address(wethUsdcPair)).sync();

        (uint112 updatedReserve0, uint112 updatedReserve1,) = IGTPair(address(wethUsdcPair)).getReserves();
        assertEq(updatedReserve0, 1 ether);
        assertEq(updatedReserve1, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                  SKIM
    //////////////////////////////////////////////////////////////*/

    function test_SkimSuccessful() public onlyFirstDepositLiquidityAndMintLP {
        address emptyAddress = makeAddr("emptyAddress");
        weth.mint(address(wethUsdcPair), 1 ether);
        usdc.mint(address(wethUsdcPair), 1 ether);

        IGTPair(wethUsdcPair).skim(emptyAddress);

        assertEq(IERC20(address(weth)).balanceOf(emptyAddress), 1 ether);
        assertEq(IERC20(address(usdc)).balanceOf(emptyAddress), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_RevertDeadlinePassedAddLiquidity() public {
        vm.expectRevert(GTRouter.GTRouter__DeadlinePassed.selector);
        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            0
        );
        vm.stopPrank();
    }

    function test_RevertDeadlinePassedRemoveLiquidity() public {
        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        vm.startPrank(firstLiquidityProvider);
        vm.expectRevert(GTRouter.GTRouter__DeadlinePassed.selector);
        router.removeLiquidity(
            address(weth),
            address(usdc),
            1,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            0
        );
        vm.stopPrank();
    }

    function test_RevertAddLiquidityLessThanMinimumAcceptedB() public {
        // On first deposit to a new pair, amounts = FIRST_DEPOSIT_WETH_AMOUNT and FIRST_DEPOSIT_USDC_AMOUNT instantly
        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_MIN_ACCEPTED_WETH_DEPOSIT,
            FIRST_MIN_ACCEPTED_USDC_DEPOSIT,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();

        weth.mint(firstLiquidityProvider, FIRST_DEPOSIT_WETH_AMOUNT);
        usdc.mint(firstLiquidityProvider, FIRST_DEPOSIT_USDC_AMOUNT);
        weth.mint(address(wethUsdcPair), 100 ether);
        vm.expectRevert(GTRouter.GTRouter__InsufficientBAmount.selector);
        vm.startPrank(firstLiquidityProvider);
        router.addLiquidity(
            address(weth),
            address(usdc),
            FIRST_DEPOSIT_WETH_AMOUNT,
            FIRST_DEPOSIT_USDC_AMOUNT,
            FIRST_DEPOSIT_WETH_AMOUNT + 1,
            FIRST_DEPOSIT_USDC_AMOUNT + 1,
            firstLiquidityProvider,
            deadline
        );
        vm.stopPrank();
    }
}

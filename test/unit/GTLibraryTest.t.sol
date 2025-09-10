// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GTRouter} from "../../src/GTRouter.sol";
import {GTLibrary} from "../../src/libraries/GTLibrary.sol";

contract GTLibraryTest is Test {
    address pair;
    GTFactory factory;
    GTRouter router;
    ERC20Mock weth;
    ERC20Mock usdc;

    address feeAddress = makeAddr("feeAddress");
    address firstLiquidityProvider = makeAddr("firstLiquidityProvider");
    address secondLiquidityProvider = makeAddr("secondLiquidityProvider");
    address thirdLiquidityProvider = makeAddr("thirdLiquidityProvider");
    address swapper = makeAddr("swapper");

    uint256 public constant FIRST_DEPOSIT_WETH_AMOUNT = 10 ether;
    uint256 public constant FIRST_DEPOSIT_USDC_AMOUNT = 20_000 ether;
    uint256 public constant FIRST_MIN_ACCEPTED_WETH_DEPOSIT = 9 ether;
    uint256 public constant FIRST_MIN_ACCEPTED_USDC_DEPOSIT = 18_000 ether;
    uint256 public constant SWAPPER_INITIAL_WETH = 1 ether;
    // uint256 public constant SWAPPER_INITIAL_USDC = 2000 ether;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint256 public deadline = block.timestamp + 10 minutes;

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        factory = new GTFactory(feeAddress, feeAddress);
        router = new GTRouter(address(factory), address(weth));
        vm.prank(address(factory));
        pair = factory.createPair(address(weth), address(usdc));

        weth.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_USDC_AMOUNT);

        weth.mint(address(swapper), SWAPPER_INITIAL_WETH);
        // usdc.mint(address(swapper), SWAPPER_INITIAL_USDC);

        vm.startPrank(firstLiquidityProvider);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        IERC20(pair).approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(swapper);
        weth.approve(address(router), type(uint256).max);
        usdc.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

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

    /*//////////////////////////////////////////////////////////////
                            GET AMOUNTS OUT
    //////////////////////////////////////////////////////////////*/
    function test_RevertInvalidPathGetAmountsOut() public {
        address[] memory path = new address[](1);
        path[0] = address(weth);
        vm.expectRevert(GTLibrary.GTLibrary__InvalidPath.selector);
        router.getAmountsOut(SWAPPER_INITIAL_WETH, path);
    }

    /*//////////////////////////////////////////////////////////////
                            GET AMOUNTS IN
    //////////////////////////////////////////////////////////////*/
    function test_RevertInvalidPathGetAmountsIn() public {
        address[] memory path = new address[](1);
        path[0] = address(weth);
        vm.expectRevert(GTLibrary.GTLibrary__InvalidPath.selector);
        router.getAmountsIn(SWAPPER_INITIAL_WETH, path);
    }

    /*//////////////////////////////////////////////////////////////
                             GET AMOUNT OUT
    //////////////////////////////////////////////////////////////*/

    function test_RevertGetAmountOutNoReserves() public {
        vm.expectRevert(GTLibrary.GTLibrary__InsufficientLiquidity.selector);
        router.getAmountOut(100, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                             GET AMOUNT IN
    //////////////////////////////////////////////////////////////*/

    function test_RevertGetAmountInNoReserves() public {
        vm.expectRevert(GTLibrary.GTLibrary__InsufficientLiquidity.selector);
        router.getAmountIn(100, 0, 0);
    }

    /*//////////////////////////////////////////////////////////////
                              SORT TOKENS
    //////////////////////////////////////////////////////////////*/

    function test_RevertIdenticalTokensSortTokens() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(weth);
        vm.expectRevert(GTLibrary.GTLibrary__IdenticalTokens.selector);
        router.getAmountsOut(SWAPPER_INITIAL_WETH, path);
    }

    function test_RevertZeroAddressToken() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(0);
        vm.expectRevert(GTLibrary.GTLibrary__TokenCannotBeZeroAddress.selector);
        router.getAmountsOut(SWAPPER_INITIAL_WETH, path);
    }

    /*//////////////////////////////////////////////////////////////
                                 QUOTE
    //////////////////////////////////////////////////////////////*/

    function test_RevertInsufficientAmountQuote() public {
        vm.expectRevert(GTLibrary.GTLibrary__InsufficientAmount.selector);
        router.quote(0, 100, 100);
    }

    function test_RevertNoReservesQuote() public {
        vm.expectRevert(GTLibrary.GTLibrary__InsufficientLiquidity.selector);
        router.quote(100, 0, 0);
    }
}

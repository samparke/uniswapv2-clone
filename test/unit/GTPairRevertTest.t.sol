// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {GTPair} from "../../src/GTPair.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGTPair} from "../../src/interfaces/IGTPair.sol";

/**
 * @notice As the GTPair has been tested within the router, these tests are focused at the reverts.
 */
contract GTPairRevertTest is Test {
    address pair;
    GTFactory factory;
    ERC20Mock weth;
    ERC20Mock usdc;
    address feeAddress = makeAddr("feeAddress");
    address firstLiquidityProvider = makeAddr("firstLiquidityProvider");
    address swapper = makeAddr("swapper");

    uint256 public constant FIRST_DEPOSIT_WETH_AMOUNT = 10 ether;
    uint256 public constant FIRST_DEPOSIT_USDC_AMOUNT = 20_000 ether;

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        factory = new GTFactory(feeAddress, feeAddress);
        vm.prank(address(factory));
        pair = factory.createPair(address(weth), address(usdc));

        weth.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_WETH_AMOUNT);
        usdc.mint(address(firstLiquidityProvider), FIRST_DEPOSIT_USDC_AMOUNT);

        vm.startPrank(firstLiquidityProvider);
        weth.approve(address(pair), type(uint256).max);
        usdc.approve(address(pair), type(uint256).max);
        IERC20(pair).approve(address(pair), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyFirstDepositLiquidityAndMintLP() {
        vm.startPrank(firstLiquidityProvider);
        IERC20(usdc).transfer(address(pair), FIRST_DEPOSIT_USDC_AMOUNT);
        IERC20(weth).transfer(address(pair), FIRST_DEPOSIT_WETH_AMOUNT);
        IGTPair(pair).mint(address(firstLiquidityProvider));
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               INITALISE
    //////////////////////////////////////////////////////////////*/

    function test_RevertInitaliseIfNotFactory() public {
        vm.expectRevert(GTPair.GTPair__MustBeFactory.selector);
        IGTPair(pair).initialise(address(weth), address(usdc));
    }

    /*//////////////////////////////////////////////////////////////
                                  SWAP
    //////////////////////////////////////////////////////////////*/

    function test_RevertAmountZeroSwap() public {
        vm.expectRevert(GTPair.GTPair__InsufficientOutputAmount.selector);
        IGTPair(pair).swap(0, 0, swapper);
    }

    function test_RevertInsufficientPoolLiquidity() public {
        vm.expectRevert(GTPair.GTPair__InsufficientPoolLiquidity.selector);
        IGTPair(pair).swap(FIRST_DEPOSIT_WETH_AMOUNT, FIRST_DEPOSIT_USDC_AMOUNT, swapper);
    }

    function test_RevertInvalidToSwap() public onlyFirstDepositLiquidityAndMintLP {
        vm.expectRevert(GTPair.GTPair__InvalidTo.selector);
        IGTPair(pair).swap(1 ether, 1 ether, address(weth));
    }
}

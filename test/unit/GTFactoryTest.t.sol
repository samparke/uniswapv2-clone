// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {GTFactory} from "../../src/GTFactory.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {GTLibrary} from "../../src/libraries/GTLibrary.sol";

contract GTFactoryTest is Test {
    GTFactory factory;
    address feeAddress = makeAddr("feeAddress");
    address feeSetter = feeAddress;
    ERC20Mock weth;
    ERC20Mock usdc;

    function setUp() public {
        weth = new ERC20Mock();
        usdc = new ERC20Mock();
        factory = new GTFactory(feeAddress, feeSetter);
    }

    /*//////////////////////////////////////////////////////////////
                         FEE ADDRESS AND SETTER
    //////////////////////////////////////////////////////////////*/

    function test_InitalFeeAddressIsCorrect() public view {
        assertEq(factory.feeAddress(), feeAddress);
    }

    function test_InitalFeeSetterIsCorrect() public view {
        assertEq(factory.feeSetter(), feeSetter);
    }

    function test_SetNewFeeSetter() public {
        vm.prank(feeSetter);
        factory.setFeeSetter(address(1));
        assertEq(factory.feeSetter(), address(1));
    }

    function test_SetFeeAddress() public {
        vm.prank(feeSetter);
        factory.setFeeAddress(address(1));
        assertEq(factory.feeAddress(), address(1));
    }

    function test_RevertIf_NotFeeSetterChangingFeeAddress() public {
        vm.expectRevert(GTFactory.GTFactory__NotFeeSetter.selector);
        factory.setFeeAddress(address(this));
    }

    function test_RevertIf_NotFeeSetterChangingFeeSetter() public {
        vm.expectRevert(GTFactory.GTFactory__NotFeeSetter.selector);
        factory.setFeeSetter(address(this));
    }

    /*//////////////////////////////////////////////////////////////
                              CREATE POOL
    //////////////////////////////////////////////////////////////*/

    function test_RevertIf_TokensAreTheSame() public {
        vm.expectRevert(GTFactory.GTFactory__TokensCannotBeTheSame.selector);
        factory.createPair(address(weth), address(weth));
    }

    function test_RevertIf_TokensAreAddressZero() public {
        vm.expectRevert(GTFactory.GTFactory__TokensZeroAddress.selector);
        factory.createPair(address(0), address(weth));
    }

    function test_RevertPairAlreadyExists() public {
        factory.createPair(address(weth), address(usdc));
        vm.expectRevert(GTFactory.GTFactory__PairAlreadyExists.selector);
        factory.createPair(address(usdc), address(weth));
    }

    function test_createPoolAndMatchesExpectedAddress() public {
        factory.createPair(address(weth), address(usdc));

        address expectedPair = GTLibrary.pairFor(address(factory), address(weth), address(usdc));
        address pair = factory.allPairs(0);

        assertEq(expectedPair, pair);
    }

    /*//////////////////////////////////////////////////////////////
                                GET PAIR
    //////////////////////////////////////////////////////////////*/

    function test_getPairAddress() public {
        factory.createPair(address(weth), address(usdc));
        address pairAddress = factory.getPair(address(weth), address(usdc));
        address expectedPairAddress = GTLibrary.pairFor(address(factory), address(weth), address(usdc));

        assertEq(pairAddress, expectedPairAddress);
    }
}

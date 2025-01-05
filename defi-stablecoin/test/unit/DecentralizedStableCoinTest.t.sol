// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;
    address public USER = makeAddr("USER");
    address public ANOTHER_USER = makeAddr("ANOTHER_USER");
    uint256 public constant USER_STARTING_BALANCE = 10 ether;

    function setUp() public {
        vm.prank(USER);
        dsc = new DecentralizedStableCoin();
        vm.deal(USER, USER_STARTING_BALANCE);
    }

    function testBurnRevertsWhenAmountIsZero() public {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin_MustBeGreaterThanZero
                .selector
        );
        vm.prank(USER);
        dsc.burn(0);
    }

    function testBurnRevertsWhenAmountExceedsBalance() public {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin_BurnAmountExceedsBalance
                .selector
        );
        vm.prank(USER);
        dsc.burn(11 ether);
    }

    function testMintRevertsWhenToAddressIsZero() public {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin_NotZeroAddress
                .selector
        );
        vm.prank(USER);
        dsc.mint(address(0), 1 ether);
    }

    function testMintRevertsWhenAmountIsZero() public {
        vm.expectRevert(
            DecentralizedStableCoin
                .DecentralizedStableCoin_MustBeGreaterThanZero
                .selector
        );
        vm.prank(USER);
        dsc.mint(USER, 0);
    }

    function testMintAddsStableCoinsToUserBalance() public {
        uint256 amount = 1 ether;
        vm.prank(USER);
        dsc.mint(ANOTHER_USER, amount);
        uint256 userBalance = dsc.balanceOf(ANOTHER_USER);
        assertEq(userBalance, amount);
    }

    function testBurnRemovesStableCoinsFromUserBalance() public {
        uint256 amount = 1 ether;
        vm.prank(USER);
        dsc.mint(USER, amount);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, amount);

        vm.prank(USER);
        dsc.burn(amount);
        userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }
}

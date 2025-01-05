//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;

    address token1;
    address token2;

    address priceFeed1;

    uint256 MAX_DEPOSITE_SIZE = type(uint96).max;
    address[] public usersWithCollaterallDeposited;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        (token1, token2) = dscEngine.getCollateralTokenAddresses();
        (priceFeed1, ) = dscEngine.getPriceFeedAddresses();
    }

    function depositCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = ERC20Mock(
            _getCollateralFromSeed(collateralSeed)
        );
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSITE_SIZE);
        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        //Double push duplicates
        usersWithCollaterallDeposited.push(msg.sender);
    }

    function redeemCollateral(
        uint256 collateralSeed,
        uint256 amountCollateral
    ) public {
        ERC20Mock collateral = ERC20Mock(
            _getCollateralFromSeed(collateralSeed)
        );
        uint256 maxCollateralToRedeem = dscEngine.getCollaterallBalanceOfUser(
            msg.sender,
            address(collateral)
        );
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral <= 0) {
            return;
        }
        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if (usersWithCollaterallDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollaterallDeposited[
            addressSeed % usersWithCollaterallDeposited.length
        ];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine
            .getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) -
            int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        amount = bound(amount, 0, uint256(maxDscToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
    }

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     MockV3Aggregator(priceFeed1).updateAnswer(newPriceInt);
    // }

    //Helpepr Functions
    function _getCollateralFromSeed(
        uint256 collateralSeed
    ) private view returns (address) {
        if (collateralSeed % 2 == 0) {
            return token1;
        } else {
            return token2;
        }
    }
}

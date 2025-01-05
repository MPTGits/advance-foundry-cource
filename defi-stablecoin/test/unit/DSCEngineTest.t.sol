//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";

contract DSCEngineTest is Test {
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    address nonCollaterallTokenAddress = makeAddr("NON COLLTERAL TOKEN");
    address public USER = makeAddr("USER");
    uint256 public constant USER_STARTING_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 1 ether;
    uint256 public constant AMOUNT_MINT = 1 ether;

    address public token1;
    address public token2;
    address public token1PriceFeed;
    address public token2PriceFeed;
    address[] tokenAddresses;
    address[] feedAddresses;

    function setUp() public {
        DeployDSCEngine deployDSCEngine = new DeployDSCEngine();
        (dsc, dscEngine, ) = deployDSCEngine.deployContract();

        (token1, token2) = dscEngine.getCollateralTokenAddresses();
        (token1PriceFeed, token2PriceFeed) = dscEngine.getPriceFeedAddresses();

        ERC20Mock(token1).mint(USER, USER_STARTING_BALANCE);
        ERC20Mock(token2).mint(USER, USER_STARTING_BALANCE);
    }

    ///////////////////////////////////////
    // Constructor Tests /////////////////
    /////////////////////////////////////

    function testRevertsIfTokenLengthDoesNotMatchPriceFeeds() public {
        tokenAddresses.push(token1);
        feedAddresses.push(token1PriceFeed);
        feedAddresses.push(token2PriceFeed);
        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch
                .selector
        );
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(token1).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(token1, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositeCollaterallRevertsWhenCollateralsValueIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.depositCollateral(token1, 0);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeGreaterThanZero.selector);
        dscEngine.depositCollateral(token2, 0);
    }

    function testDepositeCollaterallRevertsWhenCollateralAddressIsIncorrect()
        public
    {
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotSupported.selector);
        dscEngine.depositCollateral(nonCollaterallTokenAddress, 1);
    }

    //////////////////////////////
    // Price Tests //////////////
    ////////////////////////////
    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(token1, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    function testGetUsdValueForCollaterralTokens() public {
        uint256 usdValueToken1 = dscEngine.getUsdValue(token1, 10);
        uint256 usdValueToken2 = dscEngine.getUsdValue(token2, 10);

        assertEq(usdValueToken1, 20000);
        assertEq(usdValueToken2, 10000);
    }

    function testgetAccountCollateralValue() public {
        vm.startPrank(USER);
        ERC20Mock(token1).approve(address(dscEngine), 10);
        ERC20Mock(token2).approve(address(dscEngine), 10);

        dscEngine.depositCollateral(token1, 10);
        dscEngine.depositCollateral(token2, 10);

        uint256 accountCollateralValue = dscEngine.getAccountCollateralValue(
            USER
        );
        vm.stopPrank();

        assertEq(accountCollateralValue, 30000);
    }

    function testCanDepositCollateralWithoutMinting()
        public
        depositedCollateral
    {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    function testmintDscWhenHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        (, int256 price, , , ) = MockV3Aggregator(token1PriceFeed)
            .latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL *
            (uint256(price) * dscEngine.getAdditionalFeedPrecision())) /
            dscEngine.getPrecision();
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBelowMinimum.selector);
        dscEngine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    // This test needs it's own custom setup
    function testRevertsIfMintFails() public {
        // Arrange - Setup
        MockFailedMintDSC mockDsc = new MockFailedMintDSC();
        tokenAddresses.push(token1);
        feedAddresses.push(token1PriceFeed);

        address owner = msg.sender;
        vm.prank(owner);
        DSCEngine mockDsce = new DSCEngine(
            tokenAddresses,
            feedAddresses,
            address(mockDsc)
        );
        mockDsc.transferOwnership(address(mockDsce));
        // Arrange - User
        vm.startPrank(USER);
        ERC20Mock(token1).approve(address(mockDsce), AMOUNT_COLLATERAL);

        mockDsce.depositCollateral(token1, AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MintFailed.selector);
        mockDsce.mintDsc(AMOUNT_MINT);
        vm.stopPrank();
    }

    function testCanDepositCollaterallAndGetAccountInformation()
        public
        depositedCollateral
    {
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dscEngine
            .getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(
            token1,
            totalCollateralValueInUsd
        );
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }
}

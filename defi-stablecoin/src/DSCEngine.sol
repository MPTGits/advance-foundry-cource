// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/*
 * @title DSC Engine
 * @author Martin Todorov
 *
 * This system is designed to be as mininimal as possible and have the tokens amintain a 1 token = 1$ pegged
 * Exogenous Collateral
 * Dollar Pegged
 * Algorithmically Stable
 *
 * It is similar to DAI if it had had no governance, no fees and was only backed by WETH and WBTC
 *
 *
 * Our system should always be "overcollateralized" to ensure that the value of the collateral is always greater than the value of the DSC minted
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for miniting and redeeming DSC as well as deposit and withdrawing of colateral
 * @notice Losely nased on MakerDAO (DAI) system
 */

contract DSCEngine is ReentrancyGuard {
    /////////////////////////////////////////
    ////// Errors ////////////////////////
    /////////////////////////////////////////
    error DSCEngine__MustBeGreaterThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
    error DSCEngine__TokenNotSupported();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBelowMinimum();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////////////////////////
    ////// Types ////////////////////////
    /////////////////////////////////////////
    using OracleLib for AggregatorV3Interface;

    /////////////////////////////////////////
    ////// State Varaibles ////////////////////////
    /////////////////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; //200% over collateralized
    uint256 private constant LIQUIDATAION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUDATION_BONUS = 10;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;
    /////////////////////////////////////////
    ////// Events ////////////////////////
    /////////////////////////////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        uint256 amount,
        address indexed token
    );

    /////////////////////////////////////////
    ////// Modifiers ////////////////////////
    /////////////////////////////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert DSCEngine__MustBeGreaterThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotSupported();
        }
        _;
    }

    /////////////////////////////////////////
    ////// Functions ////////////////////////
    /////////////////////////////////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthMismatch();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*
     * @notice Follows CEI
     * @notice This function is used to deposit collateral into the system
     * @param tokenCollateralAddress The address of the token to be deposited
     * @param amountCollateral The amount of the token to be deposited
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @param tokenCollateralAddress The address of the token to be deposited
     * @param amountCollateral The amount of the token to be deposited
     * @param amountDsctoMint The amount of DSC to mint
     * @notice This function will deposit collateral and mint DSC
     */
    function depositCollaterallAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDsctoMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDsctoMint);
    }

    /*
     *@param tokenCollaterallAddress The address of the token to be redemeed
     *@param amountCollateral The amount of the token to be redeemed
     *@param amountDscToBrun The amount of DSC to burn
     *@notice This function will burn DSC and redeem collateral in one transaction
     */
    function redeemColaterallForDsc(
        address tokenCollaterallAddress,
        uint256 amountCollateral,
        uint256 amountDscToBrun
    ) external {
        burnDsc(amountDscToBrun);
        redeemCollateral(tokenCollaterallAddress, amountCollateral);
        //Redeem collateral already checks health factor
    }

    // CEI: Check, Effects, Interact
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollaterall
    ) public moreThanZero(amountCollaterall) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollaterall,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @notice Follows CEI
     * @param amountDscToMint The amount of DSC to mint
     * @notice They must have more collateral vlaue than the minimum threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // If they minted too much
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     *@param collateral The address of the collateral token
     *@param user The address of the user to liquidate
     *@param debtToCover The amount of DSC to cover
     *@notice This function will liquidate a user if their health factor is below the minimum
     *@notice You can partially liquidate a user
     *@notice You will get a liquidation bonus if you liquidate a user that is below the minimum health factor
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startinUserHealthFactor = _healthFactor(user);
        if (startinUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmuntFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );
        //We want to five the liqudator a 10% bonus
        uint256 bonusCollateral = (tokenAmuntFromDebtCovered *
            LIQUDATION_BONUS) / LIQUIDATAION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmuntFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startinUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(user);
    }

    function getHealthFactor() external view {}

    /////////////////////////////////////////
    ////// Private & Internal View Functions ////////////////////////
    /////////////////////////////////////////

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /*
     *Returns how close to liquidation a user is
     * If user goes bellow 1, they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        //total DSC minted
        // total collateral values
        (
            uint256 totalDscMinted,
            uint256 totalCollateralValueInUsd
        ) = _getAccountInformation(user);
        return
            _calculateHealthFactor(totalDscMinted, totalCollateralValueInUsd);
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorBelowMinimum();
        }
    }

    function _calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) internal pure returns (uint256) {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATAION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollaterall,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][
            tokenCollateralAddress
        ] -= amountCollaterall;
        emit CollateralRedeemed(
            from,
            to,
            amountCollaterall,
            tokenCollateralAddress
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollaterall
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*
     * @dev Low-level internal function, do not call unless function calling it checks for health factor broken
     */
    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    /////////////////////////////////////////
    ////// Public & External View Functions ////////////////////////
    /////////////////////////////////////////
    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
    }

    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.stalePriceCheck();
        //1 ETH = 1000$
        // The returned value from CL will be 1000 * 1e8
        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getCollateralTokenAddresses()
        external
        view
        returns (address, address)
    {
        return (s_collateralTokens[0], s_collateralTokens[1]);
    }

    function getPriceFeedAddresses() external view returns (address, address) {
        return (
            s_priceFeeds[s_collateralTokens[0]],
            s_priceFeeds[s_collateralTokens[1]]
        );
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.stalePriceCheck();
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function calculateHealthFactor(
        uint256 totalDscMinted,
        uint256 collateralValueInUsd
    ) external pure returns (uint256) {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getAccountInformation(
        address user
    ) external view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    function getCollaterallBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}

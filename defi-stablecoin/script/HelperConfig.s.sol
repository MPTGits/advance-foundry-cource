// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {console} from "forge-std/console.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address token1;
        address token2;
        address token1_usd_price_feed;
        address token2_usd_price_feed;
        uint256 deployerKey;
    }

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_KEY =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor() {
        getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(
        uint256 chainId
    ) public returns (NetworkConfig memory) {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            activeNetworkConfig = getSepoliaNetworkConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaNetworkConfig()
        public
        view
        returns (NetworkConfig memory)
    {
        NetworkConfig memory networkConfig = NetworkConfig({
            token1: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81, //WETH
            token2: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063, // WBTC
            token1_usd_price_feed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            token2_usd_price_feed: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
        return networkConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.token1_usd_price_feed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator token1UsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            ETH_USD_PRICE
        );
        ERC20Mock token1 = new ERC20Mock();

        MockV3Aggregator token2UsdPriceFeed = new MockV3Aggregator(
            DECIMALS,
            BTC_USD_PRICE
        );
        ERC20Mock token2 = new ERC20Mock();

        vm.stopBroadcast();

        return
            NetworkConfig({
                token1: address(token1),
                token2: address(token2),
                token1_usd_price_feed: address(token1UsdPriceFeed),
                token2_usd_price_feed: address(token2UsdPriceFeed),
                deployerKey: DEFAULT_ANVIL_KEY
            });
    }
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {BoxV2} from "../src/BoxV2.sol";
import {BoxV1} from "../src/BoxV1.sol";

contract UpgradeBox is Script {
    function run() external returns (address) {
        address mostRecentDeployed = DevOpsTools.get_most_recent_deployment(
            "ERC1967Proxy",
            block.chainid
        );

        vm.startBroadcast();
        BoxV2 box = new BoxV2();
        vm.stopBroadcast();
        address proxy = upgradeBox(mostRecentDeployed, address(box));
    }

    function upgradeBox(address _proxy, address _box) public returns (address) {
        vm.startBroadcast();
        BoxV1 proxy = BoxV1(_proxy);
        proxy.upgradeToAndCall(address(_box), "");
        vm.stopBroadcast();
        return _proxy;
    }
}

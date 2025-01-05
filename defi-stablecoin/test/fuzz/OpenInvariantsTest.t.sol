// //SPDX-License-Identifier: MIT

// //1. Total suply of DSC should be less than the total value of collateral
// //2. Getter view functions should never revert <- evergreen invariant

// pragma solidity ^0.8.19;

// import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSCEngine} from "../../script/DeployDSCEngine.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {HelperConfig} from "../../script/HelperConfig.s.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// contract OpenInvariantsTest is StdInvariant, Test {
//     DeployDSCEngine deloyer;
//     DSCEngine dscEngine;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address token1;
//     address token2;

//     function setUp() external {
//         deloyer = new DeployDSCEngine();
//         (dsc, dscEngine, config) = deloyer.deployContract();
//         (token1, token2, , , ) = config.activeNetworkConfig();
//         targetContract(address(dscEngine));
//     }

//     function invariantProtocolMustHaveMoreValueThanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 token1Deposited = IERC20(token1).balanceOf(address(dscEngine));
//         uint256 token2Deposited = IERC20(token2).balanceOf(address(dscEngine));

//         uint256 token1Value = dscEngine.getUsdValue(
//             address(token1),
//             token1Deposited
//         );
//         uint256 token2Value = dscEngine.getUsdValue(
//             address(token2),
//             token2Deposited
//         );

//         assert(totalSupply <= token1Value + token2Value);
//     }
// }

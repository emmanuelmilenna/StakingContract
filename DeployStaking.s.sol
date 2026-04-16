
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {StakingContract} from "../src/StakingContract.sol";

contract DeployStaking is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        StakingContract staking = new StakingContract();
        vm.stopBroadcast();
        
        console.log("StakingContract deployed to:", address(staking));
    }
} 
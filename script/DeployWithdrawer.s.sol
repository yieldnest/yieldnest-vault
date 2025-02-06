// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "./ProxyUtils.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {WithdrawerConfig} from "./config/WithdrawerConfig.sol";

contract DeployWithdrawer is Script, MainnetActors {
    using stdJson for string;

    error InvalidRules();

    address public deployer;
    Withdrawer public implementation;
    Withdrawer public withdrawer;
    MainnetActors public actors;
    Provider public provider;

    function label() public view returns (string memory) {
        return string.concat("Withdrawer-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "deployer", deployer);
        vm.serializeAddress(label(), "provider", address(provider));
        vm.serializeAddress(label(), "implementation", address(implementation));
        vm.serializeAddress(label(), "proxy", address(withdrawer));
        vm.serializeAddress(label(), "proxyAdmin", ProxyUtils.getProxyAdmin(address(withdrawer)));
        vm.serializeAddress(label(), "timelock", MC.TIMELOCK);

        string memory jsonOutput = vm.serializeAddress(label(), label(), address(withdrawer));

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        vm.startBroadcast();
        deployer = msg.sender;

        implementation = new Withdrawer();

        // Deploy the proxy
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), MC.TIMELOCK, "");

        withdrawer = Withdrawer(payable(address(proxy)));

        provider = new Provider();

        WithdrawerConfig.configure(withdrawer, address(provider), MC.TIMELOCK, deployer, IActors(address(this)));

        saveDeployment();

        vm.stopBroadcast();
    }
}

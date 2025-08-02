// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "./ProxyUtils.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";
import {WithdrawerConfigurer} from "src/configures/WithdrawerConfigurer.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetActors} from "script/Actors.sol";

contract DeployWithdrawer is Script {
    using stdJson for string;

    address public deployer;
    Withdrawer public withdrawer;

    function label() public view returns (string memory) {
        return string.concat("Withdrawer-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment(address implementation, address proxy, address proxyAdmin) internal {
        vm.serializeAddress(label(), "deployer", msg.sender);
        vm.serializeAddress(label(), "implementation", implementation);
        vm.serializeAddress(label(), "proxy", proxy);
        vm.serializeAddress(label(), "proxyAdmin", proxyAdmin);
        string memory jsonOutput = vm.serializeAddress(label(), label(), address(withdrawer));

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        deployer = msg.sender;

        vm.startBroadcast();
        address implementation = address(new Withdrawer());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, MC.TIMELOCK, "");
        withdrawer = Withdrawer(payable(address(proxy)));
        vm.stopBroadcast();

        address proxyAdmin = ProxyUtils.getProxyAdmin(address(proxy));

        console.log("Configuring Withdrawer at address:", address(withdrawer));
        WithdrawerConfigurer configurer = new WithdrawerConfigurer();
        configurer.configure(withdrawer, address(IVault(MC.YNBNBX).provider()), MC.TIMELOCK, new MainnetActors());

        console.log("Withdrawer configured at address:", address(withdrawer));

        saveDeployment(implementation, address(proxy), proxyAdmin);
    }
}

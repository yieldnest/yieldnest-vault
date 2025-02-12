// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "./ProxyUtils.sol";

contract DeployReferralAdapter is Script {
    using stdJson for string;

    address public deployer;
    XReferralAdapter public referralAdapter;

    function label() public view returns (string memory) {
        return string.concat("XReferralAdapter-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment(address implementation, address proxy, address proxyAdmin) internal {
        vm.serializeAddress(label(), "deployer", msg.sender);
        vm.serializeAddress(label(), "implementation", implementation);
        vm.serializeAddress(label(), "proxy", proxy);
        vm.serializeAddress(label(), "proxyAdmin", proxyAdmin);
        string memory jsonOutput = vm.serializeAddress(label(), label(), address(referralAdapter));

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        deployer = msg.sender;

        vm.startBroadcast();
        address implementation = address(new XReferralAdapter());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            implementation,
            // TODO: add your ADMIN address here
            0x72fdBD51085bDa5eEEd3b55D1a46E2e92f0837a5,
            ""
        );
        referralAdapter = XReferralAdapter(address(proxy));
        vm.stopBroadcast();

        address proxyAdmin = ProxyUtils.getProxyAdmin(address(proxy));
        saveDeployment(implementation, address(proxy), proxyAdmin);
    }
}

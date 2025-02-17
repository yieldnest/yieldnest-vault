// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors, IActors} from "script/Actors.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "./ProxyUtils.sol";
import {Vault} from "src/Vault.sol";

contract DeployViewer is Script, MainnetActors {
    using stdJson for string;

    address public deployer;
    MaxVaultViewer public viewerImplementation;
    MaxVaultViewer public viewer;

    Vault public vault;

    function label() public view returns (string memory) {
        return string.concat("viewer-ynETHx-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "viewer-proxyAdmin", ProxyUtils.getProxyAdmin(address(viewer)));
        vm.serializeAddress(label(), "viewer-proxy", address(viewer));
        vm.serializeAddress(label(), "viewer-implementation", address(viewerImplementation));

        vm.serializeAddress(label(), "vault-proxyAdmin", ProxyUtils.getProxyAdmin(address(vault)));
        vm.serializeAddress(label(), "vault-proxy", address(vault));

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        deployer = msg.sender;
        vault = Vault(payable(MC.YNETHX));

        vm.startBroadcast();

        viewerImplementation = new MaxVaultViewer();

        bytes memory initData = abi.encodeWithSelector(MaxVaultViewer.initialize.selector, address(vault), deployer);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(viewerImplementation), ADMIN, initData);

        viewer = MaxVaultViewer(payable(address(proxy)));

        // grant temporary roles to deployer
        viewer.grantRole(viewer.UPDATER_ROLE(), deployer);

        // setup underlying assets
        address[] memory underlyingAssets = new address[](5);
        underlyingAssets[0] = MC.WETH;
        underlyingAssets[1] = MC.STETH;
        underlyingAssets[2] = MC.WSTETH;
        underlyingAssets[3] = MC.OETH;
        underlyingAssets[4] = MC.WOETH;

        // NOTE: the following call will fail if ynETHx vault is not upgraded
        viewer.addUnderlyingAssets(underlyingAssets);

        // grant roles to admin
        viewer.grantRole(viewer.UPDATER_ROLE(), ADMIN);
        viewer.grantRole(viewer.DEFAULT_ADMIN_ROLE(), ADMIN);

        // renounce roles from deployer
        viewer.renounceRole(viewer.DEFAULT_ADMIN_ROLE(), deployer);
        viewer.renounceRole(viewer.UPDATER_ROLE(), deployer);

        vm.stopBroadcast();

        saveDeployment();
    }
}

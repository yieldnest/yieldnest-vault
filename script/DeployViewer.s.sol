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
        return string.concat("viewer-ynUSDx-", Strings.toString(block.chainid));
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
        vault = Vault(payable(MC.YNUSDx));

        vm.startBroadcast();

        viewerImplementation = new MaxVaultViewer();

        bytes memory initData = abi.encodeWithSelector(MaxVaultViewer.initialize.selector, address(vault), deployer);

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(viewerImplementation), UPDATER, initData);

        viewer = MaxVaultViewer(payable(address(proxy)));

        // grant temporary roles to deployer
        viewer.grantRole(viewer.UPDATER_ROLE(), deployer);

        // setup underlying assets
        address[] memory underlyingAssets = new address[](1);
        underlyingAssets[0] = MC.USDC;

        // NOTE: the following call will fail if ynUSDx vault is not upgraded
        viewer.addUnderlyingAssets(underlyingAssets);

        // grant roles to admin
        viewer.grantRole(viewer.UPDATER_ROLE(), UPDATER);
        viewer.grantRole(viewer.DEFAULT_ADMIN_ROLE(), UPDATER);

        // renounce roles from deployer
        viewer.renounceRole(viewer.DEFAULT_ADMIN_ROLE(), deployer);
        viewer.renounceRole(viewer.UPDATER_ROLE(), deployer);

        vm.stopBroadcast();

        saveDeployment();
    }
}
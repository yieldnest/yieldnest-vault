// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {IProvider} from "src/interface/IProvider.sol";
import {IActors, MainnetActors} from "script/Actors.sol";
import {L1Contracts, IContracts} from "script/Contracts.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {BaseVaultViewer} from "src/utils/BaseVaultViewer.sol";
import {Vault} from "src/Vault.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

abstract contract BaseScript is Script {
    using stdJson for string;

    uint256 public minDelay;
    IActors public actors;
    IContracts public contracts;

    address public deployer;
    TimelockController public timelock;
    IProvider public rateProvider;
    Vault public vault;
    Vault public implementation;
    address public vaultProxyAdmin;

    IVaultViewer public viewer;
    IVaultViewer public viewerImplementation;
    address public viewerProxyAdmin;

    Withdrawer public withdrawer;
    Withdrawer public withdrawerImplementation;
    address public withdrawerProxyAdmin;

    error UnsupportedChain();
    error InvalidSetup();

    // needs to be overriden by child script
    function symbol() public view virtual returns (string memory);

    function _setup() public virtual {
        deployer = msg.sender;

        minDelay = 1 days;
        MainnetActors _actors = new MainnetActors();
        actors = IActors(_actors);
        contracts = IContracts(new L1Contracts());
    }

    function _loadDeployment() internal virtual {
        if (!vm.isFile(_deploymentFilePath())) {
            return;
        }
        string memory jsonInput = vm.readFile(_deploymentFilePath());

        deployer = address(vm.parseJsonAddress(jsonInput, ".deployer"));
        timelock = TimelockController(payable(address(vm.parseJsonAddress(jsonInput, ".timelock"))));
        rateProvider = IProvider(payable(address(vm.parseJsonAddress(jsonInput, ".rateProvider"))));

        viewer = IVaultViewer(payable(address(vm.parseJsonAddress(jsonInput, ".viewer-proxy"))));
        viewerImplementation = IVaultViewer(payable(address(vm.parseJsonAddress(jsonInput, ".viewer-implementation"))));
        viewerProxyAdmin = address(vm.parseJsonAddress(jsonInput, ".viewer-proxyAdmin"));

        vault = Vault(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy")))));
        implementation =
            Vault(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-implementation")))));
        vaultProxyAdmin = address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxyAdmin")));

        withdrawer = Withdrawer(payable(address(vm.parseJsonAddress(jsonInput, ".withdrawer-proxy"))));
        withdrawerImplementation =
            Withdrawer(payable(address(vm.parseJsonAddress(jsonInput, ".withdrawer-implementation"))));
        withdrawerProxyAdmin = address(vm.parseJsonAddress(jsonInput, ".withdrawer-proxyAdmin"));
    }

    function _deploymentFilePath() internal view virtual returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json");
    }
}

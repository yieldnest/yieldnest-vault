// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {IProvider} from "src/interface/IProvider.sol";
import {IActors, MainnetActors} from "script/Actors.sol";
import {L1Contracts, IContracts} from "script/Contracts.sol";
import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {BaseVaultViewer} from "src/utils/BaseVaultViewer.sol";
import {Vault} from "src/Vault.sol";

import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";

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

    WrappedToken public wusdc;
    WrappedToken public wusdcImplementation;
    address public wusdcProxyAdmin;

    error UnsupportedChain();
    error InvalidSetup(string message);

    // needs to be overriden by child script
    function symbol() public view virtual returns (string memory);

    function _setup() public virtual {
        deployer = msg.sender;

        minDelay = 1 days;
        MainnetActors _actors = new MainnetActors();
        actors = IActors(_actors);
        contracts = IContracts(new L1Contracts());
    }

    function _verifySetup() public view virtual {
        if (block.chainid != 1) {
            revert UnsupportedChain();
        }
        if (address(actors) == address(0) || address(contracts) == address(0) || address(timelock) == address(0)) {
            revert InvalidSetup("Required contracts not initialized");
        }
    }

    function _deployViewer(address viewerImplementation_) internal virtual {
        if (address(vault) == address(0) || address(viewerImplementation_) == address(0)) {
            revert InvalidSetup("Vault or viewer implementation not set");
        }

        viewerImplementation = IVaultViewer(payable(viewerImplementation_));

        bytes memory initData = abi.encodeWithSelector(BaseVaultViewer.initialize.selector, address(vault));

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(viewerImplementation), actors.ADMIN(), initData);

        viewer = IVaultViewer(payable(address(proxy)));

        viewerProxyAdmin = ProxyUtils.getProxyAdmin(address(viewer));
    }

    function _deployTimelockController() internal virtual {
        address[] memory proposers = new address[](1);
        proposers[0] = actors.PROPOSER_1();

        address[] memory executors = new address[](1);
        executors[0] = actors.EXECUTOR_1();

        address admin = actors.ADMIN();

        timelock = new TimelockController(minDelay, proposers, executors, admin);
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

        wusdc = WrappedToken(payable(address(vm.parseJsonAddress(jsonInput, ".wusdc-proxy"))));
        wusdcImplementation = WrappedToken(payable(address(vm.parseJsonAddress(jsonInput, ".wusdc-implementation"))));
        wusdcProxyAdmin = address(vm.parseJsonAddress(jsonInput, ".wusdc-proxyAdmin"));
    }

    function _deploymentFilePath() internal view virtual returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json");
    }

    function _saveDeployment() internal virtual {
        vm.serializeString(symbol(), "symbol", symbol());
        vm.serializeAddress(symbol(), "deployer", deployer);
        vm.serializeAddress(symbol(), "admin", actors.ADMIN());
        vm.serializeAddress(symbol(), "timelock", address(timelock));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));

        vm.serializeAddress(symbol(), "viewer-proxyAdmin", ProxyUtils.getProxyAdmin(address(viewer)));
        vm.serializeAddress(symbol(), "viewer-proxy", address(viewer));
        vm.serializeAddress(symbol(), "viewer-implementation", address(viewerImplementation));

        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxyAdmin"), ProxyUtils.getProxyAdmin(address(vault)));
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(vault));

        vm.serializeAddress(symbol(), "wusdc-proxyAdmin", ProxyUtils.getProxyAdmin(address(wusdc)));
        vm.serializeAddress(symbol(), "wusdc-proxy", address(wusdc));
        vm.serializeAddress(symbol(), "wusdc-implementation", address(wusdcImplementation));

        string memory jsonOutput =
            vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(implementation));

        vm.writeJson(jsonOutput, _deploymentFilePath());
    }
}

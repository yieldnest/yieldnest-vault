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
    Vault public vaultProxy;
    Vault public vaultImplementation;
    address public vaultProxyAdmin;

    Withdrawer public withdrawerProxy;
    Withdrawer public withdrawerImplementation;
    address public withdrawerProxyAdmin;

    IVaultViewer public viewerProxy;
    IVaultViewer public viewerImplementation;
    address public viewerProxyAdmin;

    address public paraswapValidator;

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

    function _verifySetup() public view virtual {
        if (block.chainid != 1) {
            revert UnsupportedChain();
        }
        if (
            address(actors) == address(0) || address(contracts) == address(0) || address(rateProvider) == address(0)
                || address(timelock) == address(0)
        ) {
            revert InvalidSetup();
        }
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

        viewerProxy = IVaultViewer(payable(address(vm.parseJsonAddress(jsonInput, ".viewer-proxy"))));
        viewerImplementation = IVaultViewer(payable(address(vm.parseJsonAddress(jsonInput, ".viewer-implementation"))));
        viewerProxyAdmin = address(vm.parseJsonAddress(jsonInput, ".viewer-proxyAdmin"));

        vaultProxy = Vault(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy")))));
        vaultImplementation =
            Vault(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-implementation")))));
        vaultProxyAdmin = address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxyAdmin")));

        withdrawerProxy = Withdrawer(payable(address(vm.parseJsonAddress(jsonInput, ".withdrawer-proxy"))));
        withdrawerImplementation =
            Withdrawer(payable(address(vm.parseJsonAddress(jsonInput, ".withdrawer-implementation"))));
        withdrawerProxyAdmin = address(vm.parseJsonAddress(jsonInput, ".withdrawer-proxyAdmin"));
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

        vm.serializeAddress(symbol(), "viewer-proxy", address(viewerProxy));
        vm.serializeAddress(symbol(), "viewer-implementation", address(viewerImplementation));
        vm.serializeAddress(symbol(), "viewer-proxyAdmin", ProxyUtils.getProxyAdmin(address(viewerProxy)));

        vm.serializeAddress(symbol(), "paraswapValidator", address(paraswapValidator));

        vm.serializeAddress(
            symbol(), string.concat(symbol(), "-proxyAdmin"), ProxyUtils.getProxyAdmin(address(vaultProxy))
        );
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(vaultProxy));

        string memory jsonOutput =
            vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(vaultImplementation));

        vm.writeJson(jsonOutput, _deploymentFilePath());
    }
}

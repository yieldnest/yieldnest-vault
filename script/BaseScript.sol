// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {IProvider} from "src/interface/IProvider.sol";
import {TestnetActors, IActors, MainnetActors} from "script/Actors.sol";
import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";
import {VaultUtils} from "script/VaultUtils.sol";

import {IVaultViewer} from "src/interface/IVaultViewer.sol";
import {BaseVaultViewer} from "src/utils/BaseVaultViewer.sol";
import {IVault} from "src/interface/IVault.sol";
import {Vault} from "src/Vault.sol";

import {TransparentUpgradeableProxy as TUP} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

import {ProxyUtils} from "script/ProxyUtils.sol";

abstract contract BaseScript is Script, VaultUtils {
    using stdJson for string;

    uint256 public minDelay;
    IActors public actors;
    IContracts public contracts;

    address public deployer;
    TimelockController public timelock;
    IProvider public rateProvider;
    Vault public vault;
    Vault public implementation;
    IVaultViewer public viewer;
    IVaultViewer public viewerImplementation;

    error UnsupportedChain();
    error InvalidSetup();

    // needs to be overriden by child script
    function symbol() public view virtual returns (string memory);

    function _setup() public {
        deployer = msg.sender;

        if (block.chainid == 97) {
            minDelay = 10 seconds;
            TestnetActors _actors = new TestnetActors();
            actors = IActors(_actors);
            contracts = IContracts(new ChapelContracts());
        }

        if (block.chainid == 56) {
            minDelay = 1 days;
            MainnetActors _actors = new MainnetActors();
            actors = IActors(_actors);
            contracts = IContracts(new BscContracts());
        }
    }

    function _verifySetup() public view {
        if (block.chainid != 56 && block.chainid != 97) {
            revert UnsupportedChain();
        }
        if (
            address(actors) == address(0) || address(contracts) == address(0) || address(rateProvider) == address(0)
                || address(timelock) == address(0)
        ) {
            revert InvalidSetup();
        }
    }

    function _deployViewer(address viewerImplementation_) internal virtual {
        if (address(vault) == address(0) || address(viewerImplementation_) == address(0)) {
            revert InvalidSetup();
        }

        viewerImplementation = IVaultViewer(payable(viewerImplementation_));

        bytes memory initData = abi.encodeWithSelector(BaseVaultViewer.initialize.selector, address(vault));

        TUP proxy = new TUP(address(viewerImplementation), actors.ADMIN(), initData);

        viewer = IVaultViewer(payable(address(proxy)));
    }

    function _deployTimelockController() internal virtual {
        address[] memory proposers = new address[](2);
        proposers[0] = actors.PROPOSER_1();
        proposers[1] = actors.PROPOSER_2();

        address[] memory executors = new address[](2);
        executors[0] = actors.EXECUTOR_1();
        executors[1] = actors.EXECUTOR_2();

        address admin = actors.ADMIN();

        timelock = new TimelockController(minDelay, proposers, executors, admin);
    }

    function _configureDefaultRoles() internal virtual {
        if (address(vault) == address(0) || actors.ADMIN() == address(0) || address(timelock) == address(0)) {
            revert InvalidSetup();
        }

        // set admin roles
        vault.grantRole(keccak256("DEFAULT_ADMIN_ROLE"), actors.ADMIN());
        vault.grantRole(keccak256("PROCESSOR_ROLE"), actors.PROCESSOR());
        vault.grantRole(keccak256("PAUSER_ROLE"), actors.PAUSER());
        vault.grantRole(keccak256("UNPAUSER_ROLE"), actors.UNPAUSER());

        // set timelock roles
        vault.grantRole(keccak256("PROVIDER_MANAGER_ROLE"), address(timelock));
        vault.grantRole(keccak256("ASSET_MANAGER_ROLE"), address(timelock));
        vault.grantRole(keccak256("BUFFER_MANAGER_ROLE"), address(timelock));
        vault.grantRole(keccak256("PROCESSOR_MANAGER_ROLE"), address(timelock));
    }

    function _configureTemporaryRoles() internal virtual {
        if (address(vault) == address(0)) {
            revert InvalidSetup();
        }
        vault.grantRole(keccak256("PROCESSOR_MANAGER_ROLE"), msg.sender);
        vault.grantRole(keccak256("PROVIDER_MANAGER_ROLE"), msg.sender);
        vault.grantRole(keccak256("ASSET_MANAGER_ROLE"), msg.sender);
        vault.grantRole(keccak256("UNPAUSER_ROLE"), msg.sender);
    }

    function _renounceTemporaryRoles() internal virtual {
        if (address(vault) == address(0)) {
            revert InvalidSetup();
        }
        vault.renounceRole(keccak256("DEFAULT_ADMIN_ROLE"), msg.sender);
        vault.renounceRole(keccak256("PROCESSOR_MANAGER_ROLE"), msg.sender);
        vault.renounceRole(keccak256("PROVIDER_MANAGER_ROLE"), msg.sender);
        vault.renounceRole(keccak256("ASSET_MANAGER_ROLE"), msg.sender);
        vault.renounceRole(keccak256("UNPAUSER_ROLE"), msg.sender);
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
        vault = Vault(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-proxy")))));
        implementation =
            Vault(payable(address(vm.parseJsonAddress(jsonInput, string.concat(".", symbol(), "-implementation")))));
    }

    function _deploymentFilePath() internal view virtual returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", symbol(), "-", Strings.toString(block.chainid), ".json");
    }

    function _saveDeployment() internal virtual {
        // minDelay
        vm.serializeString(symbol(), "symbol", symbol());
        vm.serializeAddress(symbol(), "deployer", msg.sender);
        vm.serializeAddress(symbol(), "admin", actors.ADMIN());
        vm.serializeAddress(symbol(), "timelock", address(timelock));
        vm.serializeAddress(symbol(), "rateProvider", address(rateProvider));

        vm.serializeAddress(symbol(), "viewer-proxyAdmin", ProxyUtils.getProxyAdmin(address(viewer)));
        vm.serializeAddress(symbol(), "viewer-proxy", address(viewer));
        vm.serializeAddress(symbol(), "viewer-implementation", address(viewerImplementation));

        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxyAdmin"), ProxyUtils.getProxyAdmin(address(vault)));
        vm.serializeAddress(symbol(), string.concat(symbol(), "-proxy"), address(vault));
        vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(implementation));

        string memory jsonOutput =
            vm.serializeAddress(symbol(), string.concat(symbol(), "-implementation"), address(implementation));

        vm.writeJson(jsonOutput, _deploymentFilePath());
    }
}

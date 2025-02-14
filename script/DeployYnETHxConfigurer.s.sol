// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {Withdrawer} from "src/withdraws/Withdrawer.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {Provider} from "src/module/Provider.sol";
import {WithdrawerConfig} from "script/config/WithdrawerConfig.sol";
import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";
import {YnETHx} from "src/YnETHx.sol";
import {VaultLib} from "src/library/VaultLib.sol";

contract DeployYnETHxConfigurer is Script, MainnetActors {
    using stdJson for string;

    error InvalidRules();

    address public deployer;
    Withdrawer public implementation;
    Withdrawer public withdrawer;
    MainnetActors public actors;
    Provider public provider;
    YnETHxConfigurer public ynethxConfigurer;
    YnETHx public ynethxImplementation;

    function label() public view returns (string memory) {
        return string.concat("ynETHx-", Strings.toString(block.chainid), "-", VaultLib.VAULT_VERSION);
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "provider", address(provider));
        vm.serializeAddress(label(), "withdrawer-implementation", address(implementation));
        vm.serializeAddress(label(), "withdrawer-proxy", address(withdrawer));
        vm.serializeAddress(label(), "withdrawer-proxyAdmin", ProxyUtils.getProxyAdmin(address(withdrawer)));
        vm.serializeAddress(label(), "timelock", MC.TIMELOCK);
        vm.serializeAddress(label(), "ynethx-configurer", address(ynethxConfigurer));
        vm.serializeAddress(label(), "ynethx-implementation", address(ynethxImplementation));
        vm.serializeAddress(label(), "ynethx-proxy", MC.YNETHX);
        vm.serializeAddress(label(), "ynethx-proxyAdmin", ProxyUtils.getProxyAdmin(MC.YNETHX));
        vm.serializeString(label(), "ynethx-upgradeAndCall", _getUpgradeAndCallData());

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function _getUpgradeAndCallData() internal returns (string memory) {
        address target = ProxyUtils.getProxyAdmin(MC.YNETHX);
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

        uint256 decimals = 18;
        uint64 baseWithdrawalFee = 0;

        bytes memory initData = abi.encodeWithSelector(YnETHx.initializeV2.selector, decimals, baseWithdrawalFee);
        bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(ynethxImplementation), initData);

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");

        uint256 delay = 86400;

        string memory upgradeJsonLabel = string.concat("upgradeAndCall-ynETHx-", Strings.toString(block.chainid));

        vm.serializeAddress(upgradeJsonLabel, "target", target);
        vm.serializeUint(upgradeJsonLabel, "value", value);
        vm.serializeBytes(upgradeJsonLabel, "data", data);
        vm.serializeBytes32(upgradeJsonLabel, "predecessor", predecessor);
        vm.serializeBytes32(upgradeJsonLabel, "salt", salt);

        string memory upgradeJsonOutput = vm.serializeUint(upgradeJsonLabel, "delay", delay);

        return upgradeJsonOutput;
    }

    function run() public {
        deployer = msg.sender;

        vm.startBroadcast();

        implementation = new Withdrawer();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), MC.TIMELOCK, "");

        withdrawer = Withdrawer(payable(address(proxy)));

        provider = new Provider();

        WithdrawerConfig.configure(withdrawer, address(provider), MC.TIMELOCK, deployer, IActors(address(this)));

        ynethxConfigurer = new YnETHxConfigurer();

        ynethxImplementation = new YnETHx();

        vm.stopBroadcast();

        saveDeployment();
    }
}

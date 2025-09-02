// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors, IActors} from "script/Actors.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";
import {Vault} from "src/Vault.sol";
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract DeployFeeHooks is Script, MainnetActors {
    using stdJson for string;

    address public deployer;
    FeeHooks public feeHooks;
    address public performanceFeeRecipient;
    address public owner;
    uint256 public performanceFee;
    IHooks.Config public config;
    Vault public vault;

    function label() public view returns (string memory) {
        return string.concat("feeHooks-ynETHx-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "feeHooks", address(feeHooks));
        vm.serializeAddress(label(), "vault", address(vault));
        vm.serializeAddress(label(), "owner", owner);
        vm.serializeAddress(label(), "performanceFeeRecipient", performanceFeeRecipient);

        string memory jsonOutput = vm.serializeAddress(label(), "deployer", deployer);

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        deployer = msg.sender;
        vault = Vault(payable(MC.YNETHX));

        config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: false,
            beforeWithdraw: false,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });

        vm.startBroadcast();

        owner = vm.parseAddress(vm.prompt("Enter the owner address"));
        performanceFee = vm.parseUint(vm.prompt("Enter the performance fee (denominated in 1e18) i.e. 1e18 = 100%"));
        performanceFeeRecipient = vm.parseAddress(vm.prompt("Enter the performance fee recipient address"));

        bool isConfigValid = vm.parseBool(vm.prompt("Is the config valid? (true/false)"));

        require(isConfigValid, "Config is not valid");

        feeHooks = new FeeHooks(address(vault), owner, performanceFee, performanceFeeRecipient, config);

        vm.stopBroadcast();

        saveDeployment();
    }
}

// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {BscContracts, ChapelContracts, IContracts} from "script/Contracts.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "lib/forge-std/src/console.sol";

import {BaseScript} from "script/BaseScript.sol";

contract GenerateSetProviderTxData is BaseScript {
    string internal _tokenSymbol;

    // needs to be overriden by child script
    function symbol() public view virtual override returns (string memory) {
        return _tokenSymbol;
    }

    function run() external {
        console.log("=== Upgrade Information ===");
        console.log("Current Block Number: %s", block.number);
        console.log("Current Chain ID: %s", block.chainid);

        _tokenSymbol = vm.envString("TOKEN");
        address newProvider = vm.envAddress("PROVIDER");

        console.log("Token Name: %s", _tokenSymbol);

        _loadDeployment();

        console.log("=== Set Provider Details ===");
        console.log("Current Provider address: %s", vm.toString(vault.provider()));
        console.log("New Provider address: %s", vm.toString(newProvider));

        // Generate calldata for setProvider(address)
        bytes memory txData = abi.encodeWithSelector(vault.setProvider.selector, newProvider);

        console.log("=== Transaction Details ===");
        console.log("Timelock: %s", vm.toString(address(timelock)));
        console.log("Target Vault: %s", vm.toString(address(vault)));
        console.log("Transaction data:");
        console.logBytes(txData);
    }
}

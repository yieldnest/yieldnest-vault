// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "lib/forge-std/src/console.sol";

import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

/**
 * @title GenerateVaultUpgradeTxData
 * @dev This script generates the transaction data needed to upgrade a specific contract in the YnLSDe system.
 *
 * USAGE:
 * --------
 * To run this script, use the following command in your terminal:
 *
 * PROFILE=mainnet TOKEN=[token symbol] NEW_IMPLEMENTATION=[implementation address] forge script
 * GenerateVaultUpgradeTxData --legacy
 *
 *
 * Where:
 * - TOKEN: The symbol of the token (e.g., ynBTCk)
 * - NEW_IMPLEMENTATION: The address of the new implementation contract
 *
 *
 *
 * EXAMPLE:
 * --------
 * FOUNDRY_PROFILE=mainnet TOKEN=ynWBNBk NEW_IMPLEMENTATION=0x43a22463517B57CE4Fd52dC6B33f7d58b8A16119 forge script
 * GenerateVaultUpgradeTxData --legacy
 *
 * This command will:
 * 1. Set the token symbol to 'ynBTCk'
 * 3. Set the new implementation address to 0x43a22463517B57CE4Fd52dC6B33f7d58b8A16119
 *
 * The script will then generate and display the necessary transaction data for the upgrade process.
 * --------
 */
contract GenerateVaultUpgradeTxData is BaseScript {
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
        address newImplementation = vm.envAddress("NEW_IMPLEMENTATION");

        console.log("Token Name: %s", _tokenSymbol);

        _loadDeployment();

        console.log("=== Contract Upgrade Details ===");
        console.log("Contract address: %s", vm.toString(address(vault)));

        console.log("New implementation: %s", vm.toString(newImplementation));

        address proxyAddress = address(vault);
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(proxyAddress);
        address proxyAdmin = ProxyUtils.getProxyAdmin(address(proxy));
        require(vaultProxyAdmin == proxyAdmin, "ProxyAdmin mismatch");

        bytes memory data = ""; // Empty data for now, can be customized if needed
        bytes memory txData =
            abi.encodeWithSelector(ProxyAdmin.upgradeAndCall.selector, address(proxy), newImplementation, data);

        console.log("=== Upgrade Transaction Details ===");
        console.log("Upgrade timelock: %s", vm.toString(address(timelock)));
        console.log("Target ProxyAdmin: %s", vm.toString(proxyAdmin));
        console.log("Upgrade transaction data:");
        console.logBytes(txData);
    }
}

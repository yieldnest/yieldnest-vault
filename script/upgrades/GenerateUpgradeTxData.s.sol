// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {console} from "lib/forge-std/src/console.sol";

import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {BaseVault} from "src/BaseVault.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
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

    // Struct to hold local variables to avoid stack too deep errors
    struct UpgradeData {
        address newImplementation;
        address newProvider;
        address newWithdrawerImplementation;
        address proxyAddress;
        address proxyAdmin;
        address withdrawerProxyAdmin;
        Withdrawer withdrawer;
        ITransparentUpgradeableProxy proxy;
        bytes txData;
        uint256 txCount;
        uint256 txIndex;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
    }

    // needs to be overriden by child script
    function symbol() public view virtual override returns (string memory) {
        return _tokenSymbol;
    }

    function run() external {
        console.log("=== Upgrade Information ===");
        console.log("Current Block Number: %s", block.number);
        console.log("Current Chain ID: %s", block.chainid);

        _tokenSymbol = vm.envString("TOKEN");
        console.log("Token Name: %s", _tokenSymbol);

        // Initialize the upgrade data struct
        UpgradeData memory data;

        // Load environment variables
        data.newImplementation = vm.envAddress("NEW_IMPLEMENTATION");
        try vm.envAddress("NEW_PROVIDER") returns (address provider) {
            data.newProvider = provider;
        } catch {
            data.newProvider = address(0);
        }

        try vm.envAddress("WITHDRAWER_IMPLEMENTATION") returns (address withdrawerImpl) {
            data.newWithdrawerImplementation = withdrawerImpl;
        } catch {
            data.newWithdrawerImplementation = address(0);
        }

        _loadDeployment();

        console.log("=== Contract Upgrade Details ===");
        console.log("Contract address: %s", vm.toString(address(vault)));
        console.log("New implementation: %s", vm.toString(data.newImplementation));

        data.proxyAddress = address(vault);
        data.proxy = ITransparentUpgradeableProxy(data.proxyAddress);
        data.proxyAdmin = ProxyUtils.getProxyAdmin(address(data.proxy));
        require(vaultProxyAdmin == data.proxyAdmin, "ProxyAdmin mismatch");

        bytes memory emptyData = ""; // Empty data for now, can be customized if needed
        data.txData = abi.encodeWithSelector(
            ProxyAdmin.upgradeAndCall.selector, address(data.proxy), data.newImplementation, emptyData
        );

        console.log("=== Upgrade Transaction Details ===");
        console.log("Upgrade timelock: %s", vm.toString(address(timelock)));
        console.log("Target ProxyAdmin: %s", vm.toString(data.proxyAdmin));
        console.log("Upgrade transaction data:");
        console.logBytes(data.txData);

        // Determine the number of transactions we need to execute
        data.txCount = 1; // Start with the vault implementation upgrade

        if (data.newProvider != address(0)) {
            data.txCount += 2; // One for vault provider, one for withdrawer provider
        }

        if (data.newWithdrawerImplementation != address(0)) {
            data.txCount += 1; // One for withdrawer implementation upgrade
        }

        // Add 2 more transactions for processAccounting on withdrawer and vault
        data.txCount += 2;

        // Create arrays for the batch transaction
        data.targets = new address[](data.txCount);
        data.values = new uint256[](data.txCount);
        data.calldatas = new bytes[](data.txCount);

        // Add vault implementation upgrade
        data.txIndex = 0;
        data.targets[data.txIndex] = data.proxyAdmin;
        data.values[data.txIndex] = 0;
        data.calldatas[data.txIndex] = data.txData;
        data.txIndex++;

        // Add withdrawer implementation upgrade if needed
        if (data.newWithdrawerImplementation != address(0)) {
            console.log("\n=== Withdrawer Upgrade Details ===");
            console.log("New withdrawer implementation: %s", vm.toString(data.newWithdrawerImplementation));

            data.withdrawerProxyAdmin = ProxyUtils.getProxyAdmin(address(data.withdrawer));
            bytes memory withdrawerUpgradeData = abi.encodeWithSelector(
                ProxyAdmin.upgradeAndCall.selector, address(data.withdrawer), data.newWithdrawerImplementation, ""
            );

            data.targets[data.txIndex] = data.withdrawerProxyAdmin;
            data.values[data.txIndex] = 0;
            data.calldatas[data.txIndex] = withdrawerUpgradeData;
            data.txIndex++;

            console.log("Withdrawer upgrade transaction data:");
            console.logBytes(withdrawerUpgradeData);
            console.log("Target ProxyAdmin for withdrawer: %s", vm.toString(data.withdrawerProxyAdmin));
        }

        // Add provider updates if needed
        if (data.newProvider != address(0)) {
            console.log("\n=== Provider Update Details ===");
            console.log("New provider address: %s", vm.toString(data.newProvider));

            // Generate the transaction data for setting the new provider on vault
            bytes memory setVaultProviderData = abi.encodeWithSelector(BaseVault.setProvider.selector, data.newProvider);

            data.targets[data.txIndex] = address(vault);
            data.values[data.txIndex] = 0;
            data.calldatas[data.txIndex] = setVaultProviderData;
            data.txIndex++;

            // Generate the transaction data for setting the new provider on withdrawer
            bytes memory setWithdrawerProviderData =
                abi.encodeWithSelector(BaseVault.setProvider.selector, data.newProvider);

            data.targets[data.txIndex] = address(data.withdrawer);
            data.values[data.txIndex] = 0;
            data.calldatas[data.txIndex] = setWithdrawerProviderData;
            data.txIndex++;

            console.log("Set provider transaction data for vault:");
            console.logBytes(setVaultProviderData);
            console.log("Target for vault setProvider: %s", vm.toString(address(vault)));

            console.log("Set provider transaction data for withdrawer:");
            console.logBytes(setWithdrawerProviderData);
            console.log("Target for withdrawer setProvider: %s", vm.toString(address(data.withdrawer)));
        }

        // Add processAccounting for withdrawer
        console.log("\n=== Process Accounting Details ===");
        bytes memory processAccountingWithdrawerData = abi.encodeWithSelector(BaseVault.processAccounting.selector);
        data.targets[data.txIndex] = address(data.withdrawer);
        data.values[data.txIndex] = 0;
        data.calldatas[data.txIndex] = processAccountingWithdrawerData;
        data.txIndex++;

        console.log("Process accounting transaction data for withdrawer:");
        console.logBytes(processAccountingWithdrawerData);
        console.log("Target for withdrawer processAccounting: %s", vm.toString(address(data.withdrawer)));

        // Add processAccounting for vault
        bytes memory processAccountingVaultData = abi.encodeWithSelector(BaseVault.processAccounting.selector);
        data.targets[data.txIndex] = address(vault);
        data.values[data.txIndex] = 0;
        data.calldatas[data.txIndex] = processAccountingVaultData;
        data.txIndex++;

        console.log("Process accounting transaction data for vault:");
        console.logBytes(processAccountingVaultData);
        console.log("Target for vault processAccounting: %s", vm.toString(address(vault)));

        // Print out the arrays in comma-separated format
        console.log("\n=== Batch Transaction Arrays ===");

        // Print targets array
        console.log("Targets: [");
        printAddressArray(data.targets);
        console.log("]");

        // Print values array
        console.log("Values: [");
        printUintArray(data.values);
        console.log("]");

        // Print calldatas array
        console.log("Calldatas: [");
        printBytesArray(data.calldatas);
        console.log("]");
    }

    function printAddressArray(address[] memory addresses) internal pure {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (i < addresses.length - 1) {
                console.log("  %s,", vm.toString(addresses[i]));
            } else {
                console.log("  %s", vm.toString(addresses[i]));
            }
        }
    }

    function printUintArray(uint256[] memory values) internal pure {
        for (uint256 i = 0; i < values.length; i++) {
            if (i < values.length - 1) {
                console.log("  %s,", values[i]);
            } else {
                console.log("  %s", values[i]);
            }
        }
    }

    function printBytesArray(bytes[] memory data) internal pure {
        for (uint256 i = 0; i < data.length; i++) {
            if (i < data.length - 1) {
                console.logBytes(data[i]);
                console.log(",");
            } else {
                console.logBytes(data[i]);
            }
        }
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vault} from "src/Vault.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "src/Common.sol";

contract PrintStateOfVault is Script {
    function logEthValue(string memory label, uint256 value) internal view {
        uint256 eth = value / 1e18;
        uint256 decimals = value % 1e18;
        string memory decimalStr = vm.toString(decimals);
        // Pad with leading zeros if needed
        while (bytes(decimalStr).length < 18) {
            decimalStr = string.concat("0", decimalStr);
        }
        // Take first 3 decimal places
        decimalStr = string.concat(".", string(bytes(decimalStr)));
        console.log(string.concat("  ETH:  ", vm.toString(eth), decimalStr, " ETH"));
    }

    function run() external {
        // Get vault instance
        Vault vault = Vault(payable(MC.YNETHX));
        
        // Get key metrics
        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        uint256 oneShareInAssets = vault.convertToAssets(1e18);
        
        // Get buffer balance
        address buffer = vault.buffer();
        uint256 bufferBalance = IERC20(buffer).balanceOf(address(vault));
        // Convert buffer balance to ETH amount using provider
        uint256 bufferBalanceInEth = vault.convertToAssets(bufferBalance);
        
        // Print results
        console.log("\n=== Vault State ===\n");
        console.log("Total Assets");
        console.log("  Wei:  ", totalAssets);
        logEthValue("Total Assets", totalAssets);
        console.log("");

        console.log("Total Supply");
        console.log("  Wei:  ", totalSupply);
        console.log("");

        console.log("Share Price");
        console.log("  Wei:  ", oneShareInAssets);
        logEthValue("Share Price", oneShareInAssets);
        console.log("");

        console.log("Buffer Balance");
        console.log("  Wei:  ", bufferBalance);
        logEthValue("Buffer Balance", bufferBalanceInEth);
        console.log("\n==================\n");
    }
}

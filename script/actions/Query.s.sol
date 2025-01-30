// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {IVault} from "src/interface/IVault.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Query is Script {
    function run() external {
        console2.log("=== Generate Processor Transaction Data ===");
        console2.log("Current Block Number: %s", block.number);
        console2.log("Current Chain ID: %s", block.chainid);

        IVault vault = IVault(MC.YNBNBX);
        uint256 totalAssets = vault.totalAssets();
        
        console2.log("\n=== Vault Total Assets ===");
        console2.log("Vault: %s", vm.toString(address(vault)));
        console2.log("Total Assets: %s", totalAssets);

        address asbnb = MC.ASBNB;
        uint256 asbnbBalance = IERC20Metadata(asbnb).balanceOf(address(vault));
        
        console2.log("\n=== ASBNB Balance ===");
        console2.log("ASBNB: %s", vm.toString(asbnb));
        console2.log("Balance: %s", asbnbBalance);

        address slisbnb = MC.SLISBNB;
        uint256 slisbnbBalance = IERC20Metadata(slisbnb).balanceOf(address(vault));
        
        console2.log("\n=== SLISBNB Balance ===");
        console2.log("SLISBNB: %s", vm.toString(slisbnb));
        console2.log("Balance: %s", slisbnbBalance);

        address ynasbnbk = MC.YNASBNBK;
        uint256 ynasbnbkBalance = IERC20Metadata(ynasbnbk).balanceOf(address(vault));
        
        console2.log("\n=== YNASBNBK Balance ===");
        console2.log("YNASBNBK: %s", vm.toString(ynasbnbk));
        console2.log("Balance: %s", ynasbnbkBalance);

        uint256 convertedAssets = vault.convertToAssets(1e18);
        
        console2.log("\n=== YNBNBX Convert 1 Share to Assets ==="); 
        console2.log("1 Share in Assets: %s", convertedAssets);

    }
}
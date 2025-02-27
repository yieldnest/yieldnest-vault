// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vault} from "src/Vault.sol";

contract GenerateDepositETHToYnETH is Script {
    function run() external {
        Vault vault = Vault(payable(MC.YNETHX));

        // amount of eth to deposit
        uint256 amount = 1 ether; // placeholder amount

        // Generate targets array
        address[] memory targets = new address[](1);    
        targets[0] = address(MC.YNETH);

        // Generate values array
        uint256[] memory values = new uint256[](1);
        values[0] = amount;

        // Generate calldata array
        bytes[] memory data = new bytes[](1);
        // calls depositETH with vault address with recipient as vault address
        data[0] = abi.encodeWithSignature("depositETH(address)", address(vault));

        // Print out the encoded processor call
        bytes memory processorCall =
            abi.encodeWithSignature("processor(address[],uint256[],bytes[])", targets, values, data);

        console.logBytes(processorCall);
    }
}

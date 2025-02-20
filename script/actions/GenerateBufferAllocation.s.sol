// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vault} from "src/Vault.sol";
import {console} from "lib/forge-std/src/console.sol";


contract GenerateBufferAllocation is Script {
    function run() external {
        // Get vault instance to access buffer address
        Vault vault = Vault(payable(MC.YNETHX));
        address buffer = vault.buffer();

        // Amount to allocate (example amount - adjust as needed)
        uint256 amount = 250 ether;

        // Generate targets array
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;        // WETH contract for approval
        targets[1] = buffer;         // Buffer contract for deposit

        // Generate values array (no ETH sent with calls)
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        // Generate calldata array
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            buffer,
            amount
        );
        data[1] = abi.encodeWithSignature(
            "deposit(uint256,address)",
            amount,
            address(vault)
        );

        // Print out the encoded processor call
        bytes memory processorCall = abi.encodeWithSignature(
            "processor(address[],uint256[],bytes[])",
            targets,
            values,
            data
        );

        console.logBytes(processorCall);
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vault} from "src/Vault.sol";

contract GenerateStakeEthInstETH is Script {
    function run() external {
        Vault vault = Vault(payable(MC.YNETHX));
        
        // amount of eth to stake
        uint256 amount = 1 ether; // placeholder amount

        // Generate targets array
        address[] memory targets = new address[](1);    
        targets[0] = MC.STETH;

        // Generate values array
        uint256[] memory values = new uint256[](1);
        values[0] = amount;

        // Generate calldata array
        bytes[] memory data = new bytes[](1);
        // calls submit on steth contract with referrer as vault address
        data[0] = abi.encodeWithSignature("submit(address)", address(vault));

        // Print out the encoded processor call
        bytes memory processorCall =
            abi.encodeWithSignature("processor(address[],uint256[],bytes[])", targets, values, data);

        console.logBytes(processorCall);
    }
}

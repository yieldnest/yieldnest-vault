// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";

contract GenerateUnwrapWETHToEth is Script {
    function run() external {
        
        // amount of weth to unwrap
        uint256 amount = 1 ether; // placeholder amount

        // Generate targets array
        address[] memory targets = new address[](1);    
        targets[0] = MC.WETH;

        // Generate values array
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        // Generate calldata array
        bytes[] memory data = new bytes[](1);
        // unwraps weth to eth
        data[0] = abi.encodeWithSignature("withdraw(uint256)", amount);

        // Print out the encoded processor call
        bytes memory processorCall =
            abi.encodeWithSignature("processor(address[],uint256[],bytes[])", targets, values, data);

        console.logBytes(processorCall);
    }
}

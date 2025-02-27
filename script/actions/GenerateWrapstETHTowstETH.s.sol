// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";

contract GenerateWrapstETHTowstETH is Script {
    function run() external {

        uint256 amount = 1 ether; // placeholder amount

        // Generate targets array
        address[] memory targets = new address[](2);    
        targets[0] = MC.STETH;
        targets[1] = MC.WSTETH;
        // Generate values array
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        // Generate calldata array
        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(MC.WSTETH), amount);
        data[1] = abi.encodeWithSignature("wrap(uint256)", amount);

        // Print out the encoded processor call
        bytes memory processorCall =
            abi.encodeWithSignature("processor(address[],uint256[],bytes[])", targets, values, data);

        console.logBytes(processorCall);
    }
}

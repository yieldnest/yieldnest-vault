// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";

contract GenerateCurveLPYearnStrategyAllocation is Script {
    function run() external {
        // Amount to allocate for each token
        uint256 amount = 1 ether; // Example amount - adjust as needed
        uint256 minOut = 2028218000000000000;

        // Generate targets array
        address[] memory targets = new address[](3);
        targets[0] = MC.YNETH; // ynETH approval
        targets[1] = MC.YNLSDE; // ynLSDe approval
        targets[2] = MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR; // Connector deposit

        // Generate values array (no ETH sent with calls)
        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        // Generate calldata array
        bytes[] memory data = new bytes[](3);

        // Approve ynETH to connector
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR, amount);

        // Approve ynLSDe to connector
        data[1] = abi.encodeWithSignature("approve(address,uint256)", MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR, amount);

        // Deposit equal amounts into connector with minimum output
        data[2] = abi.encodeWithSignature("deposit(uint256,uint256,uint256)", amount, amount, minOut);

        // Print out the encoded processor call
        bytes memory processorCall =
            abi.encodeWithSignature("processor(address[],uint256[],bytes[])", targets, values, data);

        console.logBytes(processorCall);
    }
}

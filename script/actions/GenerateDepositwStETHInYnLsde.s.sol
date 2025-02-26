// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Script} from "lib/forge-std/src/Script.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";

interface IWstETH {
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}

contract GenerateDepositwStETHInYnLsde is Script {
    function run() external {
        // Get vault instance
        Vault vault = Vault(payable(MC.YNETHX));

        // amount of weth to unwrap
        uint256 amount = IERC20(MC.WSTETH).balanceOf(address(vault)); // placeholder amount

        // Generate targets array
        address[] memory targets = new address[](2);    
        targets[0] = MC.WSTETH;
        targets[1] = MC.YNLSDE;

        // Generate values array
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        // Generate calldata array
        bytes[] memory data = new bytes[](2);
        // unwraps weth to eth
        data[0] = abi.encodeWithSignature("approve(address,uint256)", address(MC.YNLSDE), amount);
        data[1] = abi.encodeWithSignature("deposit(address,uint256,address)", address(MC.WSTETH), amount, address(vault));
        // Print out the encoded processor call
        bytes memory processorCall =
            abi.encodeWithSignature("processor(address[],uint256[],bytes[])", targets, values, data);

        console.logBytes(processorCall);

    }
}
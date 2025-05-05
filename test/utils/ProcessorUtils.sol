// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IVault} from "src/interface/IVault.sol";

library ProcessorUtils {

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /**
     * @notice Allocates assets to an ERC4626 strategy
     * @param vault The vault address
     * @param asset The asset address to approve
     * @param strategy The ERC4626 strategy address
     * @param amount The amount to allocate
     * @param processor The processor address
     */
    function allocateToERC4626(
        address vault,
        address asset,
        address strategy,
        uint256 amount,
        address processor
    ) internal {

        Vm vm = Vm(CHEATCODE_ADDRESS);
        address[] memory targets = new address[](2);
        targets[0] = asset;
        targets[1] = strategy;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", strategy, amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, vault);

        vm.prank(processor);
        IVault(vault).processor(targets, values, data);
    }
}
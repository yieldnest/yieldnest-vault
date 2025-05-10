// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

library UpgradeUtils {

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    function timelockUpgrade(
        TimelockController timelockController,
        address owner,
        address target,
        address newImplementation
    ) external {
        Vm vm = Vm(CHEATCODE_ADDRESS);


        address proxyAdmin = ProxyUtils.getProxyAdmin(target);

        bytes memory _data = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)",
            target,
            newImplementation,
            ""
        );
        vm.startPrank(owner);
        timelockController.schedule(
            proxyAdmin, // target
            0, // value
            _data,
            bytes32(0), // predecessor
            bytes32(0), // salt
            timelockController.getMinDelay() // delay
        );
        vm.stopPrank();

        uint256 minDelay = 3 days;
        vm.warp(block.timestamp + minDelay);

        vm.startPrank(owner);
        timelockController.execute(
            proxyAdmin, // target
            0, // value
            _data,
            bytes32(0), // predecessor
            bytes32(0) // salt
        );
        vm.stopPrank();
    }

}
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Script, stdJson} from "lib/forge-std/src/Script.sol";

import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";

import {Strings} from "lib/openzeppelin-contracts/contracts/utils/Strings.sol";

contract DeployReferralAdapter is Script {
    using stdJson for string;

    address public deployer;
    XReferralAdapter public referralAdapter;

    function label() public view returns (string memory) {
        return string.concat("x-referral-adapter-", Strings.toString(block.chainid));
    }

    function deploymentFilePath() internal view returns (string memory) {
        return string.concat(vm.projectRoot(), "/deployments/", label(), ".json");
    }

    function saveDeployment() internal {
        vm.serializeAddress(label(), "deployer", msg.sender);

        string memory jsonOutput = vm.serializeAddress(label(), label(), address(referralAdapter));

        vm.writeJson(jsonOutput, deploymentFilePath());
    }

    function run() public {
        deployer = msg.sender;

        referralAdapter = new XReferralAdapter();

        saveDeployment();
    }
}

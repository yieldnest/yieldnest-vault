// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {VaultFactory} from "src/VaultFactory.sol";
import {LocalActors} from "script/Actors.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20} from "src/Common.sol";

contract DeployFactory is LocalActors {
    address[] public proposers = new address[](2);
    address[] public executors = new address[](2);

    function deploy(uint256 minDelay) public returns (VaultFactory) {
        address singleVaultImpl = address(new SingleVault());

        proposers = [PROPOSER_1, PROPOSER_2];
        executors = [EXECUTOR_1, EXECUTOR_2];

        VaultFactory factory = new VaultFactory(singleVaultImpl, proposers, executors, minDelay, ADMIN);
        return factory;
    }

    function getProposers() public returns (address[] memory) {
        proposers = [PROPOSER_1, PROPOSER_2];
        return proposers;
    }

    function getExecutors() public returns (address[] memory) {
        executors = [EXECUTOR_1, EXECUTOR_2];
        return executors;
    }
}

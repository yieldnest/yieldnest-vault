// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20, TimelockControllerUpgradeable} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {DeployFactory, VaultFactory} from "test/helpers/DeployFactory.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";

contract TimelockTest is Test, LocalActors, TestConstants {
    SingleVault public vault;
    IERC20 public asset;

    enum OperationState {
        Unset,
        Waiting,
        Ready,
        Done
    }

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = IERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));
        DeployFactory deployFactory = new DeployFactory();
        VaultFactory factory = deployFactory.deploy(0);

        address vaultAddress = factory.createSingleVault(
            asset,
            VAULT_NAME,
            VAULT_SYMBOL,
            ADMIN,
            OPERATOR,
            0, // admin tx time delay
            deployFactory.getProposers(),
            deployFactory.getExecutors()
        );
        vault = SingleVault(payable(vaultAddress));
    }

    function testScheduleTransaction() public {
        uint256 amount = 100 * 10 ** 18;
        asset.approve(address(vault), amount);
        vault.deposit(amount, ADMIN);

        uint256 shares = vault.balanceOf(ADMIN);

        // schedule a transaction
        address target = address(asset);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, ADMIN, shares);
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");
        uint256 delay = 1;

        vm.startPrank(PROPOSER_1);
        vault.schedule(target, value, data, predecessor, salt, delay);
        vm.stopPrank();

        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
        // timestamp should be block 1 of the foundry test, plus 0 for the delay.
        assertEq(vault.getTimestamp(id), 2);

        assert(vault.getOperationState(id) == TimelockControllerUpgradeable.OperationState.Waiting);

        assertEq(vault.isOperationReady(id), false);
        assertEq(vault.isOperationDone(id), false);
        assertEq(vault.isOperation(id), true);

        uint256 previousBalance = asset.balanceOf(ADMIN);

        //execute the transaction
        vm.warp(10);
        vm.startPrank(EXECUTOR_1);
        vault.execute(target, value, data, predecessor, salt);

        uint256 currentBalance = asset.balanceOf(ADMIN);
        uint256 expectedBalance = currentBalance - previousBalance;

        // // Verify the transaction was executed successfully
        assertEq(shares, expectedBalance);
        assertEq(vault.isOperationReady(id), false);
        assertEq(vault.isOperationDone(id), true);
        assert(vault.getOperationState(id) == TimelockControllerUpgradeable.OperationState.Done);
    }
}

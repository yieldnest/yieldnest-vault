// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IERC20, TimelockControllerUpgradeable} from "src/Common.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {LocalActors} from "script/Actors.sol";
import {ChapelContracts} from "script/Contracts.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {SingleVault, ISingleVault} from "src/SingleVault.sol";
import {IVaultFactory} from "src/IVaultFactory.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {SetupHelper} from "test/helpers/Setup.sol";

contract TimelockTest is Test, LocalActors, TestConstants, ChapelContracts {
    SingleVault public vault;
    MockERC20 public asset;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = MockERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault(asset);
    }

    function testScheduleTransaction() public {
        uint256 amount = 100 * 10 ** 18;
        asset.mint(amount);
        asset.approve(address(vault), amount);
        address USER = address(33);

        vault.deposit(amount, USER);

        uint256 shares = vault.balanceOf(USER);

        // schedule a transaction
        address target = address(asset);
        uint256 value = 0;
        address kernelVault = address(3);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, kernelVault, shares);
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

        uint256 previousBalance = asset.balanceOf(kernelVault);

        //execute the transaction
        vm.warp(10);
        vm.startPrank(EXECUTOR_1);
        vault.execute(target, value, data, predecessor, salt);

        uint256 currentBalance = asset.balanceOf(kernelVault);
        uint256 expectedBalance = currentBalance - previousBalance;

        // // Verify the transaction was executed successfully
        assertEq(shares, expectedBalance);
        assertEq(vault.isOperationReady(id), false);
        assertEq(vault.isOperationDone(id), true);
        assert(vault.getOperationState(id) == TimelockControllerUpgradeable.OperationState.Done);
    }
}

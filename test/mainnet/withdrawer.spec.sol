// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IERC20, Math} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IWithdrawalQueueManager, IRedemptionAssetsVault} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IProvider} from "src/interface/IProvider.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {OriginWithdrawalLib} from "src/library/OriginWithdrawalLib.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {BaseWithdrawerMainnetTest} from "test/mainnet/BaseWithdrawerTest.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {IynEigen} from "test/interface/external/yieldnest/IynEigen.sol";

/**
 * @notice Tests for the Withdrawer contract deployed with ynETHx
 *
 */
contract WithdrawerMainnetTest is BaseWithdrawerMainnetTest {
    function getWithdrawer() public override returns (Withdrawer) {
        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);

        _initVault(withdrawer);
        return withdrawer;
    }

    /**
     * @notice Test to verify the version of the Withdrawer contract
     * @dev This test ensures that the deployed Withdrawer contract has the correct version
     */
    function test_check_withdrawer_version() public {
        Withdrawer withdrawer = getWithdrawer();

        // Assert that the Withdrawer contract has the correct version
        assertEq(withdrawer.STRATEGY_VERSION(), "0.2.0", "Withdrawer should have version 0.2.0");
    }

    function test_withdraw_ynLSDE(uint256 depositAmount) public {
        vm.assume(depositAmount > 1e9);
        vm.assume(depositAmount < 100_000 ether);
        address asset = MC.YNLSDE;
        uint256 initialVaultYnLSDE = IERC20(asset).balanceOf(address(vault));
        uint256 initialWithdrawerYnLSDE = IERC20(asset).balanceOf(address(withdrawer));

        address alice = makeAddr("alice");

        // Get wstETH and deposit into ynLSDE
        deal(MC.WSTETH, alice, depositAmount);
        vm.startPrank(alice);
        IERC20(MC.WSTETH).approve(MC.YNLSDE, depositAmount);
        IynEigen(MC.YNLSDE).deposit(MC.WSTETH, depositAmount, alice);

        // Deposit ynLSDE into ynETHx vault
        uint256 ynLSDeBalance = IERC20(MC.YNLSDE).balanceOf(alice);
        IERC20(MC.YNLSDE).approve(address(vault), ynLSDeBalance);
        vault.depositAsset(MC.YNLSDE, ynLSDeBalance, address(this));
        vm.stopPrank();

        vault.processAccounting();

        // Have processor send ynLSDE to withdrawer
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = MC.YNLSDE;
        values[0] = 0;
        data[0] = abi.encodeCall(IERC20.approve, (address(withdrawer), ynLSDeBalance));

        targets[1] = address(withdrawer);
        values[1] = 0;
        data[1] = abi.encodeCall(IVault.depositAsset, (MC.YNLSDE, ynLSDeBalance, address(vault)));

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();

        assertEq(
            IERC20(MC.YNLSDE).balanceOf(address(vault)),
            initialVaultYnLSDE,
            "Vault ynLSDE balance should match initial balance"
        );

        assertEq(
            IERC20(MC.YNLSDE).balanceOf(address(withdrawer)),
            initialWithdrawerYnLSDE + ynLSDeBalance,
            "Withdrawer ynLSDE balance should match initial plus deposited amount"
        );

        withdrawer.processAccounting();
        vault.processAccounting();
    }
}

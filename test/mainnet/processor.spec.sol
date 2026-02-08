// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, Math} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {IynEigen} from "test/interface/external/yieldnest/IynEigen.sol";
import {IWithdrawalsProcessor} from "test/interface/external/yieldnest/IWithdrawalsProcessor.sol";
import {IWithdrawalQueueManager} from "src/interface/IWithdrawalQueueManager.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract ProcessorIntegrationTest is BaseIntegrationTest {
    Withdrawer public withdrawer;

    uint256 ERROR_MARGIN = 1e4;

    IWithdrawalsProcessor public withdrawalsProcessor;

    address keeper;

    function setUp() public override {
        super.setUp();

        withdrawer = VaultVerification.getWithdrawer(vault);

        withdrawalsProcessor = IWithdrawalsProcessor(MC.YNLSDE_WITHDRAWALS_PROCESSOR);

        keeper = makeAddr("keeper");

        // Grant KEEPER_ROLE to keeper
        vm.startPrank(ADMIN);
        withdrawalsProcessor.grantRole(withdrawalsProcessor.KEEPER_ROLE(), keeper);
        vm.stopPrank();

        withdrawer.processAccounting();
        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_withdraw_allExisting_ynLSDe() public {
        uint256 ynLSDeBalance = IERC20(MC.YNLSDE).balanceOf(address(vault));

        if (ynLSDeBalance == 0) {
            vm.startPrank(ADMIN);
            vault.grantRole(vault.ASSET_MANAGER_ROLE(), ADMIN);

            uint256 ynLSDeIndex = vault.getAsset(MC.YNLSDE).index;

            vault.updateAsset(ynLSDeIndex, IVault.AssetUpdateFields({active: true}));
            vm.stopPrank();

            // Deposit some ynLSDE to the vault
            uint256 depositAmount = 1e18;
            deal(MC.YNLSDE, address(this), depositAmount);
            IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
            vault.depositAsset(MC.YNLSDE, depositAmount, address(this));
            ynLSDeBalance = IERC20(MC.YNLSDE).balanceOf(address(vault));
        }
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            uint256 vaultTotalAssetsBefore = vault.totalAssets();
            uint256 withdrawerTotalAssetsBefore = withdrawer.totalAssets();

            withdrawer.processAccounting();
            vault.processAccounting();

            // Approve and deposit ynLSDE to withdrawer
            targets[0] = MC.YNLSDE;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(withdrawer), ynLSDeBalance));

            targets[1] = address(withdrawer);
            values[1] = 0;
            data[1] = abi.encodeCall(IVault.depositAsset, (MC.YNLSDE, ynLSDeBalance, address(vault)));

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, data);
            vm.stopPrank();

            withdrawer.processAccounting();
            vault.processAccounting();

            assertApproxEqRel(
                vault.totalAssets(),
                vaultTotalAssetsBefore,
                ERROR_MARGIN,
                "Vault total assets should not change after deposit to withdrawer"
            );

            assertApproxEqRel(
                withdrawer.totalAssets(),
                withdrawerTotalAssetsBefore + IynEigen(MC.YNLSDE).previewRedeem(ynLSDeBalance),
                ERROR_MARGIN,
                "Withdrawer total assets should increase by deposit amount in ETH terms"
            );
        }

        {
            // If eigenStrategyManager does not have STAKING_NODES_WITHDRAWER_ROLE on queueManager, have eigenStrategyManager grant the role to queueManager
            bytes32 STAKING_NODES_WITHDRAWER_ROLE = keccak256("STAKING_NODES_WITHDRAWER_ROLE");
            address eigenStrategyManager = 0x92D904019A92B0Cafce3492Abb95577C285A68fC;

            // Only grant the role if not already granted
            if (
                !IAccessControl(eigenStrategyManager).hasRole(
                    STAKING_NODES_WITHDRAWER_ROLE, address(withdrawalsProcessor)
                )
            ) {
                vm.startPrank(ADMIN); // Assume ADMIN/timelock can grant on eigenStrategyManager
                IAccessControl(eigenStrategyManager).grantRole(
                    STAKING_NODES_WITHDRAWER_ROLE, address(withdrawalsProcessor)
                );
                vm.stopPrank();
            }
        }

        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            uint256 vaultTotalAssetsBefore = vault.totalAssets();
            uint256 withdrawerTotalAssetsBefore = withdrawer.totalAssets();

            // Approve and request withdrawal for ynLSDE
            targets = new address[](2);
            values = new uint256[](2);
            data = new bytes[](2);

            targets[0] = MC.YNLSDE;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER, ynLSDeBalance));

            targets[1] = MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER;
            values[1] = 0;
            data[1] = abi.encodeWithSignature("requestWithdrawal(uint256)", ynLSDeBalance);

            vm.startPrank(PROCESSOR);
            withdrawer.processor(targets, values, data);
            vm.stopPrank();

            withdrawer.processAccounting();
            vault.processAccounting();

            assertApproxEqRel(
                vault.totalAssets(),
                vaultTotalAssetsBefore,
                ERROR_MARGIN,
                "Vault total assets should not change after requesting withdrawal"
            );

            assertApproxEqRel(
                withdrawer.totalAssets(),
                withdrawerTotalAssetsBefore,
                ERROR_MARGIN,
                "Withdrawer total assets should not change after requesting withdrawal"
            );

            // Assert that the ynLSDe balance in withdrawer is 0
            assertEq(
                IERC20(MC.YNLSDE).balanceOf(address(withdrawer)),
                0,
                "ynLSDe balance in withdrawer should be 0 after withdrawal request"
            );

            {
                uint256 lastTokenId = IWithdrawalQueueManager(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER)._tokenIdCounter() - 1;
                IWithdrawalQueueManager.WithdrawalRequest memory withdrawalRequest =
                    IWithdrawalQueueManager(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER).withdrawalRequest(lastTokenId);
                assertEq(
                    withdrawalRequest.amount, ynLSDeBalance, "Withdrawal request amount should match requested amount"
                );
                assertEq(
                    withdrawalRequest.feeAtRequestTime,
                    IWithdrawalQueueManager(MC.YNLSDE_WITHDRAWAL_QUEUE_MANAGER).withdrawalFee(),
                    "Withdrawal request fee should match current withdrawal fee"
                );
                assertEq(
                    withdrawalRequest.processed,
                    false,
                    "Withdrawal request should not be processed immediately after creation"
                );
            }
        }

        uint256 ynLSETotalAssetsBefore = vault.totalAssets();
        while (true) {
            uint256 pendingWithdrawalRequests;
            bool hasPendingWithdrawalRequests = true;
            try withdrawalsProcessor.getPendingWithdrawalRequests() returns (uint256 _pendingWithdrawalRequests) {
                pendingWithdrawalRequests = _pendingWithdrawalRequests;
            } catch {
                hasPendingWithdrawalRequests = false;
            }
            if (!hasPendingWithdrawalRequests) {
                break;
            }

            IWithdrawalsProcessor.QueueWithdrawalsArgs memory args = withdrawalsProcessor.getQueueWithdrawalsArgs();

            vm.startPrank(keeper);
            withdrawalsProcessor.queueWithdrawals(args);
            vm.stopPrank();

            // Assert that ynLSE totalAssets stays constant after every loop
            assertApproxEqRel(
                vault.totalAssets(),
                ynLSETotalAssetsBefore,
                1,
                "ynLSE total assets should not change after queueWithdrawals"
            );
        }
        // Assert again at the end
        assertApproxEqRel(
            vault.totalAssets(),
            ynLSETotalAssetsBefore,
            1,
            "ynLSE total assets should not change at the end of queueWithdrawals loops"
        );
    }
}

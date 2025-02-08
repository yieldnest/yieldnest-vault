// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHxVault} from "src/YnETHxVault.sol";
import {IVault} from "src/interface/IVault.sol";

import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";

contract VaultConfigureUpgradeTest is Test, MainnetActors {

    Vault vault;
    Withdrawer withdrawer;

    function test_configure() public {
        vault = Vault(payable(MC.YNETHX));
        uint256 previousTotalAssets = vault.totalAssets();

        {
            vm.expectRevert();
            vault.VAULT_VERSION();
        }

        {
            // upgrade the vault
            Vault vaultImpl = Vault(payable(new YnETHxVault()));

            TimelockController timelock = TimelockController(payable(MC.TIMELOCK));

            // schedule a proxy upgrade transaction on the timelock
            // the traget is the proxy admin for the max Vault Proxy Contract
            address target = MC.PROXY_ADMIN;
            uint256 value = 0;

            bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

            bytes memory initData = abi.encodeWithSelector(YnETHxVault.initializeV2.selector, 18, 0);
            bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(vaultImpl), initData);

            bytes32 predecessor = bytes32(0);
            bytes32 salt = keccak256("chad");

            uint256 delay = 86400;

            vm.startPrank(PROPOSER_1);
            timelock.schedule(target, value, data, predecessor, salt, delay);
            vm.stopPrank();

            bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
            assert(timelock.getOperationState(id) == TimelockController.OperationState.Waiting);

            assertEq(timelock.isOperationReady(id), false);
            assertEq(timelock.isOperationDone(id), false);
            assertEq(timelock.isOperation(id), true);

            //execute the transaction
            // solhint-disable-next-line not-rely-on-time
            vm.warp(block.timestamp + 86401);
            vm.startPrank(EXECUTOR_1);
            timelock.execute(target, value, data, predecessor, salt);
            vm.stopPrank();

            // Verify the transaction was executed successfully
            assertEq(timelock.isOperationReady(id), false);
            assertEq(timelock.isOperationDone(id), true);
            assert(timelock.getOperationState(id) == TimelockController.OperationState.Done);
        }

        {
            // configure the vault
            Vault newVault = Vault(payable(MC.YNETHX));

            assertEq(newVault.symbol(), "ynETHx");

            assertTrue(newVault.paused(), "Vault should be paused");

            YnETHxConfigurer configurer = new YnETHxConfigurer();
            SetupWithdrawer setup = new SetupWithdrawer();
            withdrawer = setup.setup();
            Provider provider = new Provider();

            vm.startPrank(ADMIN);
            newVault.grantRole(newVault.DEFAULT_ADMIN_ROLE(), address(configurer));
            vm.stopPrank();

            configurer.configure(address(provider), address(withdrawer));
        }

        {
            // verify the upgrade was successful
            Vault newVault = Vault(payable(MC.YNETHX));

            assertFalse(newVault.paused(), "Vault should not be paused");

            newVault.processAccounting();

            // Verify the upgrade was successful
            uint256 newTotalAssets = newVault.totalAssets();

            assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");
            assertEq(
                keccak256(bytes(vault.VAULT_VERSION())), keccak256(bytes("0.2.0")), "Vault version should be 0.1.2"
            );
        }

        verify_configuration();

        verifyWithdrawerConfiguration(vault, withdrawer);
    }


    function verify_configuration() internal {
        // Verify core vault configuration
        assertEq(vault.alwaysComputeTotalAssets(), false);
        assertEq(vault.countNativeAsset(), true);
        assertEq(vault.decimals(), 18);
        assertEq(vault.baseWithdrawalFee(), 1e5); // 0.1%

        // Verify deposit assets
        address[] memory activeAssets = new address[](3);
        activeAssets[0] = MC.WETH;
        activeAssets[1] = MC.YNETH;
        activeAssets[2] = MC.YNLSDE;

        for (uint256 i = 0; i < activeAssets.length; i++) {
            IVault.AssetParams memory asset = vault.getAsset(activeAssets[i]);
            assertTrue(asset.active);
            assertEq(asset.decimals, 18);
        }

        address[] memory inactiveAssets = new address[](5);
        inactiveAssets[0] = MC.EULER_WETH_22_VAULT;
        inactiveAssets[1] = MC.CURVE_LP_YNETH_YNLSDE_STRATEGY;
        inactiveAssets[2] = address(withdrawer);
        inactiveAssets[3] = MC.WSTETH;
        inactiveAssets[4] = MC.WOETH;

        for (uint256 i = 0; i < inactiveAssets.length; i++) {
            IVault.AssetParams memory asset = vault.getAsset(inactiveAssets[i]);
            assertFalse(asset.active);
            assertEq(asset.decimals, 18);
        }

        // Verify total number of assets
        address[] memory assets = vault.getAssets();
         // WETH, YNETH, YNLSDE, EULER_WETH_22_VAULT, CURVE_LP_YNETH_YNLSDE_STRATEGY, withdrawer, WSTETH, WOETH, STETH, OETH
        assertEq(assets.length, 10);
    }

    function verifyWithdrawerConfiguration(
        Vault vault,
        Withdrawer withdrawer
    ) internal {
        // WIP

        // Verify withdrawer configuration
        assertTrue(Withdrawer(withdrawer).hasRole(Withdrawer(withdrawer).ALLOCATOR_ROLE(), address(vault)));

        // Verify withdrawer deposit assets
        {
            IVault.AssetParams memory asset = Withdrawer(withdrawer).getAsset(MC.WETH);
            assertTrue(asset.active);
            assertEq(asset.decimals, 18);
            assertTrue(Withdrawer(withdrawer).getAssetWithdrawable(MC.WETH));
        }
        address[] memory assets = new address[](9);
        assets[0] = MC.YNETH;
        assets[1] = MC.YNLSDE;
        assets[2] = MC.WOETH;
        assets[3] = MC.OETH;
        assets[4] = MC.WSTETH;
        assets[5] = MC.STETH;
        assets[6] = MC.METH;
        assets[7] = MC.SFRXETH;
        assets[8] = MC.WETH;

        for (uint256 i = 0; i < assets.length; i++) {
            IVault.AssetParams memory asset = Withdrawer(withdrawer).getAsset(assets[i]);
            assertTrue(asset.active);
            assertEq(asset.decimals, 18);
            if (assets[i] == MC.WETH) {
                assertTrue(Withdrawer(withdrawer).getAssetWithdrawable(assets[i]));
            } else {
                assertFalse(Withdrawer(withdrawer).getAssetWithdrawable(assets[i]));
            }
        }
    }
}

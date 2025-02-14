// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController, IERC20} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHx} from "src/YnETHx.sol";
import {IVault} from "src/interface/IVault.sol";
import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {RolesVerification} from "script/verification/RolesVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {console} from "lib/forge-std/src/console.sol";
contract VaultConfigureUpgradeTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    Withdrawer public withdrawer;
    TimelockController public timelock;

    function setUp() public {
        vault = Vault(payable(MC.YNETHX));
         timelock = TimelockController(payable(MC.TIMELOCK));
         uint256 previousTotalAssets = vault.totalAssets();
       
        {
            vm.expectRevert();
            vault.VAULT_VERSION();
        }

        _upgradeVault();

   

            assertEq(vault.symbol(), "ynETHx");

            assertTrue(vault.paused(), "Vault should be paused");

            YnETHxConfigurer configurer = new YnETHxConfigurer();
            SetupWithdrawer setup = new SetupWithdrawer();
            withdrawer = setup.setup();
            Provider provider = new Provider();

            vm.startPrank(ADMIN);
            vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(configurer));

            configurer.configure(address(provider), address(withdrawer));
            vm.stopPrank();

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
    }

    function _upgradeVault() internal {
 // upgrade the vault
            Vault vaultImpl = Vault(payable(new YnETHx()));

            // schedule a proxy upgrade transaction on the timelock
            // the traget is the proxy admin for the max Vault Proxy Contract
            address target = MC.PROXY_ADMIN;
            uint256 value = 0;

            bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

            bytes memory initData = abi.encodeWithSelector(YnETHx.initializeV2.selector, 18, 0);
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

    function test_configure() public view {
        // verify the configuration was successful
        IActors actors = IActors(payable(address(this)));

        VaultVerification.verifyProvider(Provider(IVault(address(vault)).provider()), withdrawer);

        VaultVerification.verifyVaultConfiguration(vault, withdrawer);

        VaultVerification.verifyRules(vault);

        // verify actors & timelock roles on vault
        RolesVerification.verifyDefaultRoles(vault, timelock, actors);
        RolesVerification.verifyRole(
            vault, actors.FEE_MANAGER(), vault.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        // verify proxy roles on vault
        RolesVerification.verifyProxyRoles(address(vault), MC.PROXY_ADMIN, address(timelock));

        // verify withdrawer config
        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);

        // verify withdrawer roles
        VaultVerification.verifyWithdrawerRules(withdrawer);

        // verify actors & timelock roles on withdrawer
        RolesVerification.verifyDefaultRoles(withdrawer, timelock, actors);
        RolesVerification.verifyRole(
            withdrawer, address(vault), withdrawer.ALLOCATOR_ROLE(), true, "YnETHx has ALLOCATOR_ROLE"
        );

        address withdrawerProxyAdmin = ProxyUtils.getProxyAdmin(address(withdrawer));

        // verify proxy roles on withdrawer
        RolesVerification.verifyProxyRoles(address(withdrawer), withdrawerProxyAdmin, address(timelock));

        // verify timelock roles
        uint256 minDelay = 1 days;
        RolesVerification.verifyTimelockRoles(timelock, actors, minDelay);
    }

    function test_deposit_ynETH() public {
        uint256 depositAmount = 1 ether;
        deal(MC.YNETH, address(this), depositAmount);
         uint256 totalAssetBefore = vault.totalAssets();
        uint256 shares = vault.convertToShares(depositAmount);
        // Log pre-deposit values
        console.log("Total assets before:", totalAssetBefore);
        console.log("Deposit amount:", depositAmount);
        console.log("Shares:", shares);
        
        IERC20(MC.YNETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNETH, depositAmount, address(this));
        vault.processAccounting();
        
        uint256 totalAssets = vault.totalAssets();
        uint256 ynEthRate = IProvider(vault.provider()).getRate(MC.YNETH);
        
        // Log post-deposit values
        console.log("Total assets after:", totalAssets);
        console.log("ynETH rate:", ynEthRate);
        console.log("Expected increase:", shares * ynEthRate / 1e18);
        console.log("Actual increase:", totalAssets - totalAssetBefore);

        assertEqThreshold(
            totalAssets, 
            totalAssetBefore + (shares * ynEthRate / 1e18), 
            5,  // Keep original small threshold
            "Total assets should match deposit amount"
        );
    }

    function test_deposit_ynLSDe() public {
        uint256 totalAssetBefore = vault.totalAssets();
        uint256 depositAmount = 1 ether;
        uint256 shares = vault.convertToShares(depositAmount);
        // vault.processAccounting();
        deal(MC.YNLSDE,address(this), depositAmount);
        // Deposit YN
          IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNLSDE, depositAmount, address(this));
        vault.processAccounting();
        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();

        uint256 ynLSDeRate = IProvider(vault.provider()).getRate(MC.YNLSDE);
        //TODO: this is returning much .2 eth higher than it should be
        assertEqThreshold(totalAssets, totalAssetBefore + (shares * ynLSDeRate / 1e18), 5,"Total assets should match deposit amount");
    }
}

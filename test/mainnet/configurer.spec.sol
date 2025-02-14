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

interface IOETHVault {
    function mint(address _asset, uint256 _amount, uint256 _minimumOusdAmount) external;
}

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

        IERC20(MC.YNETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNETH, depositAmount, address(this));
        vault.processAccounting();
        
        uint256 totalAssets = vault.totalAssets();
        uint256 ynEthRate = IProvider(vault.provider()).getRate(MC.YNETH);
        
           assertEqThreshold(
            totalAssets, 
            totalAssetBefore + (depositAmount * ynEthRate / 1e18), 
            5,  // Keep original small threshold
            "Total assets should match deposit amount"
        );
    }

    function test_deposit_ynLSDe() public {
        uint256 totalAssetBefore = vault.totalAssets();
        uint256 depositAmount = 1 ether;

        deal(MC.YNLSDE,address(this), depositAmount);
        // Deposit YN
          IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNLSDE, depositAmount, address(this));
        vault.processAccounting();
        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();

        uint256 ynLSDeRate = IProvider(vault.provider()).getRate(MC.YNLSDE);
        assertEqThreshold(totalAssets, totalAssetBefore + (depositAmount * ynLSDeRate / 1e18), 5,"Total assets should match deposit amount");
    }

    function test_deposit_wETH() public {
     uint256 totalAssetBefore = vault.totalAssets();
        uint256 depositAmount = 1 ether;

        deal(MC.WETH,address(this), depositAmount);
        // Deposit YN
          IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));
        vault.processAccounting();
        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();

        uint256 WETHRate = IProvider(vault.provider()).getRate(MC.WETH);
        assertEqThreshold(totalAssets, totalAssetBefore + (depositAmount * WETHRate / 1e18), 5,"Total assets should match deposit amount");
    }

    function test_donate_whitlisted_Assets() public {
        uint256 donationAmount = 1 ether;
        uint256 totalAssetBefore = vault.totalAssets();
        
        // Donate the 10 whitelisted assets to the vault
        address[] memory whitelistedAssets = new address[](10);
        whitelistedAssets[0] = MC.WETH;
        vm.label(MC.WETH, "WETH");
        deal(MC.WETH, address(this), donationAmount * 10);
        whitelistedAssets[1] = MC.YNETH;
        vm.label(MC.YNETH, "YNETH");
        deal(MC.YNETH, address(this), donationAmount);

        whitelistedAssets[2] = MC.YNLSDE;
        vm.label(MC.YNLSDE, "YNLSDE");
        deal(MC.YNLSDE, address(this), donationAmount);

        whitelistedAssets[3] = MC.STETH;
        {
            // Deal  to and convert to stETH
            vm.deal(address(this), donationAmount);
            (bool success,) = MC.STETH.call{value: donationAmount}("");
            assertTrue(success, "stETH deposit failed");
            vm.stopPrank();
        }
        vm.label(MC.STETH, "STETH");

        whitelistedAssets[4] = MC.EULER_WETH_22_VAULT;
        vm.label(MC.EULER_WETH_22_VAULT, "EULER_WETH_22_VAULT");
        deal(MC.EULER_WETH_22_VAULT, address(this), donationAmount);

        whitelistedAssets[5] = MC.CURVE_LP_YNETH_YNLSDE_STRATEGY;
        vm.label(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, "CURVE_LP_YNETH_YNLSDE_STRATEGY");
        deal(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY, address(this), donationAmount);

        whitelistedAssets[6] = MC.WSTETH;
        vm.label(MC.WSTETH, "WSTETH");
        deal(MC.WSTETH, address(this), donationAmount);
        
        whitelistedAssets[7] = MC.OETH;
        vm.label(MC.OETH, "OETH");
        // {
        //  //TODO: figure out how to get OETH this reverts
        //     IERC20(MC.WETH).approve(MC.OETH, donationAmount);
        //    IOETHVault(MC.OETH).mint(MC.WETH, donationAmount, 1);
        // }
        whitelistedAssets[8] = MC.WOETH;
        vm.label(MC.WOETH, "WOETH");
        deal(MC.WOETH, address(this), donationAmount);

        whitelistedAssets[9] = MC.SMOKEHOUSE_WSTETH;
        vm.label(MC.SMOKEHOUSE_WSTETH, "SMOKEHOUSE_WSTETH");
        deal(MC.SMOKEHOUSE_WSTETH, address(this), donationAmount);

        for (uint256 i = 0; i < whitelistedAssets.length; i++) {
            if (whitelistedAssets[i] != MC.OETH) {
            IERC20(whitelistedAssets[i]).transfer(address(vault), donationAmount);
            }
        }

        vault.processAccounting();

        uint256 totalSupply = vault.totalSupply();
        uint256 totalExpectedAssets;
        for (uint256 i = 0; i < whitelistedAssets.length; i++) {
            if (whitelistedAssets[i] != MC.OETH) {
            uint256 rate = IProvider(vault.provider()).getRate(whitelistedAssets[i]);
            totalExpectedAssets += donationAmount * rate / 1e18;
            }
        }
        assertEq(totalSupply, totalAssetBefore + totalExpectedAssets, "Total assets should equal total supply");
    }
}

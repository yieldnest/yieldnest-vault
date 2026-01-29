// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {console} from "lib/forge-std/src/console.sol";

contract VaultMainnetUpgradeWithdrawerTest is BaseIntegrationTest {
    // Implementation addresses
    Vault public vaultImplementation;
    Withdrawer public withdrawerImplementation;

    function setUp() public override {
        super.setUp();
    }

    function upgradeVaultAndWithdrawer() internal {
        {
            vaultImplementation = new Vault();
            UpgradeUtils.timelockUpgrade(
                TimelockController(payable(TIMELOCK)), ADMIN, address(vault), address(vaultImplementation)
            );
        }

        {
            withdrawerImplementation = new Withdrawer();
            Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);
            UpgradeUtils.timelockUpgrade(
                TimelockController(payable(TIMELOCK)), ADMIN, address(withdrawer), address(withdrawerImplementation)
            );
        }
    }

    function test_Withdrawer_Upgrade_Implementation_Set_Correctly() public {
        upgradeVaultAndWithdrawer();

        // Verify the withdrawer implementation was upgraded correctly
        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);
        address currentWithdrawerImpl = ProxyUtils.getImplementation(address(withdrawer));
        assertEq(
            currentWithdrawerImpl, address(withdrawerImplementation), "Withdrawer implementation not set correctly"
        );
    }

    function test_Withdrawer_Upgrade_View_Functions() public {
        upgradeVaultAndWithdrawer();

        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);

        // Test the ALLOCATOR_ROLE is assigned to the vault
        assertTrue(
            withdrawer.hasRole(withdrawer.ALLOCATOR_ROLE(), address(vault)),
            "Vault should have ALLOCATOR_ROLE in withdrawer"
        );

        // Test the provider function
        address provider = withdrawer.provider();
        assertEq(IProvider(provider).getRate(MC.WETH), 1e18, "Provider rate for WETH should be 1e18");

        // Test the paused function
        bool isPaused = withdrawer.paused();
        assertFalse(isPaused, "Withdrawer should not be paused");

        // Test the owner of the withdrawer proxy
        assertEq(
            ProxyAdmin(ProxyUtils.getProxyAdmin(address(withdrawer))).owner(),
            TIMELOCK,
            "Owner of the withdrawer proxy admin should be TIMELOCK"
        );

        // Test the version function
        assertEq(withdrawer.STRATEGY_VERSION(), "0.3.1", "Withdrawer version should be 0.3.1");
    }

    function test_Withdrawer_Upgrade_Access_Control() public {
        upgradeVaultAndWithdrawer();

        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);

        // Test admin role
        assertTrue(
            withdrawer.hasRole(withdrawer.DEFAULT_ADMIN_ROLE(), MainnetActors.ADMIN),
            "Admin role should be set correctly"
        );

        // Test processor role
        assertTrue(
            withdrawer.hasRole(withdrawer.PROCESSOR_ROLE(), MainnetActors.PROCESSOR),
            "Processor role should be set correctly"
        );

        // Test pauser role
        assertTrue(
            withdrawer.hasRole(withdrawer.PAUSER_ROLE(), MainnetActors.PAUSER), "Pauser role should be set correctly"
        );

        // Test unpauser role
        assertTrue(
            withdrawer.hasRole(withdrawer.UNPAUSER_ROLE(), MainnetActors.UNPAUSER),
            "Unpauser role should be set correctly"
        );
    }

    function test_Withdrawer_Upgrade_State_Unchanged() public {
        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);

        address providerBefore = withdrawer.provider();
        bool pausedBefore = withdrawer.paused();

        // Perform the upgrade
        upgradeVaultAndWithdrawer();

        address providerAfter = withdrawer.provider();
        bool pausedAfter = withdrawer.paused();

        // Assert that state remains unchanged after the upgrade
        assertEq(providerAfter, providerBefore, "Provider address should remain unchanged after upgrade");
        assertEq(pausedAfter, pausedBefore, "Paused state should remain unchanged after upgrade");
    }
}

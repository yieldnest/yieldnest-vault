// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {IValidator} from "src/interface/IValidator.sol";

import {Etches} from "test/mainnet/helpers/Etches.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";

contract SetupVault is Test, MainnetActors, Etches {
    function deploy() public returns (Vault) {
        // Deploy implementation contract
        Vault implementation = new Vault();

        // Deploy transparent proxy
        bytes memory initData = abi.encodeWithSelector(
            Vault.initialize.selector, MainnetActors.ADMIN, "ynBNB MAX", "ynBNBx", 18, 0, true, true
        );
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(implementation), address(MainnetActors.ADMIN), initData);

        // Cast proxy to Vault type
        Vault vault = Vault(payable(address(proxy)));

        assertEq(vault.symbol(), "ynBNBx");

        configureMainnet(vault);

        return vault;
    }

    function configureMainnet(Vault vault) internal {
        // etch to mock ETHRate provider and Buffer
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // test cannot unpause vault without provider
        vm.expectRevert();
        vault.unpause();

        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WBNB, true);
        vault.addAsset(MC.BUFFER, false);
        vault.addAsset(MC.YNBNBK, true);
        vault.addAsset(MC.BNBX, true);
        vault.addAsset(MC.SLISBNB, true);

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](5);
        uint256 i = 0;

        // configure processor rules
        rules[i++] = BaseRules.getDepositRule(MC.BUFFER, address(vault));
        rules[i++] = BaseRules.getDepositRule(MC.YNBNBK, address(vault));
        rules[i++] = BaseRules.getWethDepositRule(MC.WBNB);
        rules[i++] = BaseRules.getApprovalRule(MC.WBNB, MC.BUFFER);
        rules[i++] = BaseRules.getApprovalRule(MC.SLISBNB, MC.YNBNBK);

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, false);

        vault.setBuffer(MC.BUFFER);

        // Unpause the vault
        vault.unpause();

        vm.stopPrank();

        vault.processAccounting();
    }
}

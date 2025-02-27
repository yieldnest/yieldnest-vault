// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";

contract SetupVault is Test, Etches, MainnetActors {
    error InvalidRules();

    function setup() public returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAX";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData =
            abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18, 0, true, false);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        vault = Vault(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));

        if (block.chainid == 31337) {
            configureLocal(vault);
        }

        if (block.chainid == 1) {
            configureMainnet(vault);
        }
    }

    function configureLocal(Vault vault) internal {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // test cannot unpause vault without buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true);
        vault.addAsset(MC.BUFFER, false);
        vault.addAsset(MC.STETH, true);
        vault.addAsset(MC.YNETH, true);

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](5);
        uint256 i = 0;

        // configure processor rules
        rules[i++] = BaseRules.getDepositRule(MC.BUFFER, address(vault));
        rules[i++] = BaseRules.getDepositRule(MC.YNETH, address(vault));
        rules[i++] = BaseRules.getWethDepositRule(MC.WETH);
        rules[i++] = BaseRules.getWethWithdrawRule(MC.WETH);
        rules[i++] = BaseRules.getApprovalRule(MC.WETH, MC.BUFFER);

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, false);

        // add strategies
        vault.setBuffer(MC.BUFFER);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }

    function configureMainnet(Vault vault) internal {
        // etch to mock the mainnet contracts
        mockAll();

        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18, 0, true);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(payable(address(vaultProxy)));

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true);
        vault.addAsset(MC.STETH, true);
        vault.addAsset(MC.BUFFER, false);

        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](4);
        uint256 i = 0;

        // configure processor rules
        rules[i++] = BaseRules.getDepositRule(MC.BUFFER, address(vault));
        rules[i++] = BaseRules.getWethDepositRule(MC.WETH);
        rules[i++] = BaseRules.getWethWithdrawRule(MC.WETH);
        rules[i++] = BaseRules.getApprovalRule(MC.WETH, MC.BUFFER);

        if (i != rules.length) {
            revert("rules length mismatch");
        }

        SafeRules.setProcessorRules(vault, rules, false);

        vault.setBuffer(MC.BUFFER);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }
}

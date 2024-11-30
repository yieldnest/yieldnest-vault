// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy, IERC20} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TestPlugin} from "test/unit/helpers/TestPlugin.sol";

contract SetupVault is Test, Etches, MainnetActors {
    function setup() public returns (Vault vault, WETH9 weth, TestPlugin plugin) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAx";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        vault = Vault(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));

        if (block.chainid == 31337) {
            plugin = configureLocal(vault);
            return (vault, weth, plugin);
        }

        if (block.chainid == 1) {
            plugin = configureMainnet(vault);
            return (vault, weth, plugin);
        }
    }

    function configureLocal(Vault vault) internal returns (TestPlugin plugin) {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        // test cannot unpause vault withtout buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, 18, true);
        vault.addAsset(MC.BUFFER, 18, false);
        vault.addAsset(MC.STETH, 18, true);

        plugin = new TestPlugin();

        // configure processor rules

        // setDepositRule(vault, MC.BUFFER, address(vault));
        // setWethDepositRule(vault, MC.WETH);

        // setApprovalRule(vault, address(vault), MC.BUFFER);
        // setApprovalRule(vault, MC.WETH, MC.BUFFER);
        // setApprovalRule(vault, address(vault), MC.YNETH);
        // setApprovalRule(vault, address(vault), MC.YNLSDE);

        // configure plugins

        TestPlugin.DepositData[] memory depositData = new TestPlugin.DepositData[](1);
        depositData[0] = TestPlugin.DepositData(MC.BUFFER, address(vault));

        TestPlugin.ApprovalData[] memory approvalData = new TestPlugin.ApprovalData[](4);
        approvalData[0] = TestPlugin.ApprovalData(address(vault), MC.BUFFER);
        approvalData[1] = TestPlugin.ApprovalData(MC.WETH, MC.BUFFER);
        approvalData[2] = TestPlugin.ApprovalData(address(vault), MC.YNETH);
        approvalData[3] = TestPlugin.ApprovalData(address(vault), MC.YNLSDE);

        TestPlugin.WethDepositData[] memory wethDepositData = new TestPlugin.WethDepositData[](1);
        wethDepositData[0] = TestPlugin.WethDepositData(MC.WETH);

        TestPlugin.PluginData memory data = TestPlugin.PluginData(depositData, approvalData, wethDepositData);

        bytes memory dataBytes = abi.encode(data);

        vault.addTarget(address(plugin), dataBytes);

        // add strategies
        vault.setBuffer(MC.BUFFER);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }

    function configureMainnet(Vault vault) internal returns (TestPlugin plugin) {
        // etch to mock the mainnet contracts

        mockAll();

        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(payable(address(vaultProxy)));

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, 18, true);
        vault.addAsset(MC.STETH, 18, true);
        vault.addAsset(MC.YNETH, 18, true);
        vault.addAsset(MC.YNLSDE, 18, true);

        plugin = new TestPlugin();
        // setDepositRule(vault, MC.BUFFER, address(vault));
        // setDepositRule(vault, MC.YNETH, address(vault));
        // setDepositRule(vault, MC.YNLSDE, address(vault));
        // setWethDepositRule(vault, MC.WETH);
        //
        // setApprovalRule(vault, address(vault), MC.BUFFER);
        // setApprovalRule(vault, MC.WETH, MC.BUFFER);
        // setApprovalRule(vault, address(vault), MC.YNETH);
        // setApprovalRule(vault, address(vault), MC.YNLSDE);

        TestPlugin.ApprovalData[] memory approvalData = new TestPlugin.ApprovalData[](4);
        approvalData[0] = TestPlugin.ApprovalData(address(vault), MC.BUFFER);
        approvalData[1] = TestPlugin.ApprovalData(MC.WETH, MC.BUFFER);
        approvalData[2] = TestPlugin.ApprovalData(address(vault), MC.YNETH);
        approvalData[3] = TestPlugin.ApprovalData(address(vault), MC.YNLSDE);

        TestPlugin.WethDepositData[] memory wethDepositData = new TestPlugin.WethDepositData[](1);
        wethDepositData[0] = TestPlugin.WethDepositData(MC.WETH);

        TestPlugin.DepositData[] memory depositData = new TestPlugin.DepositData[](3);
        depositData[0] = TestPlugin.DepositData(MC.BUFFER, address(vault));
        depositData[1] = TestPlugin.DepositData(MC.YNETH, address(vault));
        depositData[2] = TestPlugin.DepositData(MC.YNLSDE, address(vault));

        TestPlugin.PluginData memory data = TestPlugin.PluginData(depositData, approvalData, wethDepositData);

        bytes memory dataBytes = abi.encode(data);

        vault.addTarget(address(plugin), dataBytes);

        vault.setBuffer(MC.BUFFER);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }
}

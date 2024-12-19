// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IValidator} from "src/interface/IValidator.sol";


interface IynETH {
    function depositETH(address receiver) external payable returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);
}

contract VaultMainnetYnETHTest is Test, AssertUtils, MainnetActors {

    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade();
        vault = Vault(payable(MC.YNETHX));

        vm.startPrank(ADMIN);
        setWethWithdrawRule();
        setYnETHDepositETHRule();
        vm.stopPrank();
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

        event Log(string,uint256);


    function test_Vault_ynETH_depositAndAllocate() public {
        // if (assets < 0.1 ether) return;
        // if (assets > 100_000 ether) return;
        uint256 assets = 1 ether;

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address assetAddress = vault.asset();
        address receiver = address(this);

        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEqThreshold(depositedShares, shares, 3, "Deposited shares should equal the converted shares");

        vm.startPrank(PROCESSOR);
        processWithrdawWeth(assets);
        processDepositYnETH(assets);

        uint256 ynEthBalance = IERC20(MC.YNETH).balanceOf(MC.YNETHX);
        emit Log("ynEthBal", ynEthBalance);
        vm.stopPrank();

        uint256 newTotalAssets = vault.totalAssets();
        assertEqThreshold(newTotalAssets, totalAssets + assets, 5, "New total assets should equal deposit amount plus original total assets");
    }

    function processWithrdawWeth(uint256 assets) public {
        // convert WETH to ETH
        address[] memory targets = new address[](1);
        targets[0] = MC.WETH;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("withdraw(uint256)", assets);

        vault.processor(targets, values, data);
    }
    function processDepositYnETH(uint256 assets) public {
        // convert WETH to ETH
        address[] memory targets = new address[](1);
        targets[0] = MC.YNETH;

        uint256[] memory values = new uint256[](1);
        values[0] = assets;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("depositETH(address)", address(vault));

        vault.processor(targets, values, data);
    }

    function setWethWithdrawRule() internal {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault.setProcessorRule(MC.WETH, funcSig, rule);
    }

    function setYnETHDepositETHRule() internal {
        bytes4 funcSig = bytes4(keccak256("depositETH(address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        address[] memory allowList = new address[](1);
        allowList[0] = MC.YNETHX; // receiver

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault.setProcessorRule(MC.YNETH, funcSig, rule);
    }

    function test_Vault_ynETH_depositETH() public {
        IynETH yneth = IynETH(payable(MC.YNETH));

        address bob = address(1776);

        vm.deal(bob, 100 ether);
        
        vm.startPrank(bob);
        // previous vault total Assets
        uint256 previousTotalAssets = vault.totalAssets();
        uint256 ynEthShares = yneth.depositETH{value: 100 ether}(bob);
        uint256 bobYnETHBalance = yneth.balanceOf(bob);

        assertEq(ynEthShares, bobYnETHBalance, "Eth deposited in ynETH should be correct");

        yneth.approve(MC.YNETHX, bobYnETHBalance);
        vault.depositAsset(MC.YNETH, bobYnETHBalance, bob);

        uint256 newTotalAssets = vault.totalAssets();
        uint256 ynEthRate = IProvider(MC.PROVIDER).getRate(MC.YNETH);

        assertEq(newTotalAssets, previousTotalAssets + (ynEthShares * ynEthRate / 1e18), "Total assets should match the previous total assets plus the equivalent ynETH shares in base denomination");
    }
}
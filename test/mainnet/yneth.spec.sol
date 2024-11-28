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
import {IERC4626} from "src/Common.sol";



contract VaultMainnetYnETHTest is Test, AssertUtils, MainnetActors {

    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        vault = setup.deploy();

        vm.startPrank(ADMIN);
        setWethWithdrawRule();
        setYnBNBkDepositRule();
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


    function test_Vault_ynBNBk_depositAndAllocate() public {
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

        uint256 ynBnbkBalance = IERC20(MC.YNBNBk).balanceOf(address(vault));
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
        
        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.WBNB, funcSig, rule);
    }

    function setYnBNBkDepositRule() internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = 
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = address(vault); // receiver

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.YNBNBk, funcSig, rule);
    }

    function test_Vault_ynBNBk_depositBNB() public {
        IERC4626 ynbnbk = IERC4626(payable(MC.YNBNBk));

        address bob = address(1776);

        vm.deal(bob, 100 ether);


        
        vm.startPrank(bob);
        // previous vault total Assets
        uint256 previousTotalAssets = vault.totalAssets();

        IERC20(MC.SLISBNB).approve(address(ynbnbk), 100 ether);
        uint256 ynBnbkShares = ynbnbk.deposit(100 ether, bob);

        uint256 bobYnBNBkBalance = ynbnbk.balanceOf(bob);

        assertEq(ynBnbkShares, bobYnBNBkBalance, "BNB deposited in ynBNBk should be correct");

        ynbnbk.approve(address(vault), bobYnBNBkBalance);
        vault.depositAsset(MC.YNBNBk, bobYnBNBkBalance, bob);

        uint256 newTotalAssets = vault.totalAssets();
        uint256 ynBnbkRate = IProvider(MC.PROVIDER).getRate(MC.YNBNBk);

        assertEq(newTotalAssets, previousTotalAssets + (ynBnbkShares * ynBnbkRate / 1e18), "Total assets should match the previous total assets plus the equivalent ynBNBk shares in base denomination");
    }
}
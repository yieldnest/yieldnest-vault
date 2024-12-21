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
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IValidator} from "src/interface/IValidator.sol";

contract VaultMainnetYnBNBkTest is Test, AssertUtils, MainnetActors {
    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        vault = setup.deploy();

        vm.startPrank(ADMIN);
        setWBNBWithdrawRule();
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

    event Log(string, uint256);

    function test_Vault_ynBNBk_depositAndAllocate(uint256 assets) public {
        if (assets < 0.1 ether) return;
        if (assets > 1000 ether) return;

        address bob = address(1776);

        vm.deal(bob, assets * 2);

        address assetAddress = MC.SLISBNB;

        // deposit BNB to SLISBNB through stake manager
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);

        vm.prank(bob);
        stakeManager.deposit{value: assets * 2}();

        vm.startPrank(bob);
        // previous vault total Assets
        uint256 previousTotalAssets = vault.totalAssets();

        IERC20(assetAddress).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(assetAddress, assets, bob);

        uint256 assetBalance = IERC20(assetAddress).balanceOf(address(vault));
        assertEq(assetBalance, assets, "Vault should hold the deposited assets");

        assertEq(vault.balanceOf(bob), depositedShares, "bob should have the correct amount of shares");

        uint256 oldTotalAssets = vault.totalAssets();
        assertApproxEqAbs(
            oldTotalAssets,
            previousTotalAssets + stakeManager.convertSnBnbToBnb(assets),
            1000,
            "New total assets should equal deposit amount plus original total assets"
        );

        assertEq(address(vault.provider()), MC.PROVIDER, "provider should match");

        assertEq(
            stakeManager.convertSnBnbToBnb(1e18),
            IProvider(MC.PROVIDER).getRate(MC.SLISBNB),
            "slisBNB rate should match"
        );

        uint256 beforeBalance = IERC20(assetAddress).balanceOf(address(MC.YNBNBK));

        vm.startPrank(PROCESSOR);

        processApproveAsset(assetAddress, assets, MC.YNBNBK);
        processDepositYnBNBk(assets);

        vm.stopPrank();

        uint256 newTotalAssets = vault.totalAssets();

        assetBalance = IERC20(assetAddress).balanceOf(address(vault));
        assertEq(assetBalance, 0, "Vault should hold the deposited assets");

        assetBalance = IERC20(assetAddress).balanceOf(address(MC.YNBNBK));
        assertEq(assetBalance, beforeBalance + assets, "Vault should hold the deposited assets");

        uint256 previewShares = Vault(payable(MC.YNBNBK)).previewDeposit(assets);
        uint256 actualShares = Vault(payable(MC.YNBNBK)).balanceOf(address(vault));

        assertEqThreshold(previewShares, actualShares, 10, "previewShares should equal actualShares");

        uint256 previewAssets = Vault(payable(MC.YNBNBK)).previewRedeem(actualShares);

        assertApproxEqAbs(
            newTotalAssets,
            previousTotalAssets + previewAssets,
            2000,
            "New total assets should equal to previous total assets plus previewAssets"
        );

        // TODO: this should be true
        // assertApproxEqAbs(
        //     newTotalAssets,
        //     oldTotalAssets,
        //     500,
        //     "previewAssets should equal to previous total assets"
        // );
    }

    function processApproveAsset(address asset, uint256 amount, address target) public {
        address[] memory targets = new address[](1);
        targets[0] = asset;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", target, amount);

        vault.processor(targets, values, data);
    }

    function processWithrdawWBNB(uint256 assets) public {
        // convert WBNB to BNB
        address[] memory targets = new address[](1);
        targets[0] = MC.WBNB;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("withdraw(uint256)", assets);

        vault.processor(targets, values, data);
    }

    function processDepositYnBNBk(uint256 assets) public {
        // deposit BNB to ynBNBk
        address[] memory targets = new address[](1);
        targets[0] = MC.YNBNBK;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("deposit(uint256,address)", assets, address(vault));

        vault.processor(targets, values, data);
    }

    function setWBNBWithdrawRule() internal {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

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

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault.setProcessorRule(MC.YNBNBK, funcSig, rule);
    }

    function test_Vault_ynBNBk_depositBNB() public {
        IERC4626 ynbnbk = IERC4626(payable(MC.YNBNBK));

        address bob = address(1776);

        vm.deal(bob, 10000 ether);

        // deposit BNB to SLISBNB through stake manager
        ISlisBnbStakeManager stakeManager = ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER);

        uint256 depositAmount = 100 ether;

        vm.prank(bob);
        stakeManager.deposit{value: depositAmount * 2}();

        vm.startPrank(bob);
        // previous vault total Assets
        uint256 previousTotalAssets = vault.totalAssets();

        IERC20(MC.SLISBNB).approve(address(ynbnbk), 100 ether);
        uint256 ynBnbkShares = ynbnbk.deposit(100 ether, bob);

        uint256 bobYnBNBkBalance = ynbnbk.balanceOf(bob);

        assertEq(ynBnbkShares, bobYnBNBkBalance, "BNB deposited in ynBNBk should be correct");

        ynbnbk.approve(address(vault), bobYnBNBkBalance);
        vault.depositAsset(MC.YNBNBK, bobYnBNBkBalance, bob);

        uint256 newTotalAssets = vault.totalAssets();
        uint256 ynBnbkRate = IProvider(MC.PROVIDER).getRate(MC.YNBNBK);

        assertEq(
            newTotalAssets,
            previousTotalAssets + (ynBnbkShares * ynBnbkRate / 1e18),
            "Total assets should match the previous total assets plus the equivalent ynBNBk shares in base denomination"
        );
    }
}

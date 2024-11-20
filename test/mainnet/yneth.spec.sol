// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault,IVault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";

contract VaultMainnetYnETHTest is Test, MainnetActors {

    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade();
        vault = Vault(payable(MC.YNETHX));
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER_STRATEGY;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.bufferStrategy(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);
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
        assertEq(convertedAssets, assets, "Converted assets should equal the original assets");

        (bool success,) = MC.WETH.call{value: assets}("");
        if (!success) revert("Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        address assetAddress = vault.asset();
        address receiver = address(this);

        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        // allocate 100% to the ynETH strategy
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.YNETH;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = assets;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("withdraw(uint256)", assets);
        data[1] = abi.encodeWithSignature("depositETH(address)", address(vault));

        vm.startPrank(ADMIN);

        setWethWithdrawRule();
        setYnETHDepositETHRule();

        vault.processor(targets, values, data);

        uint256 ynEthBalance = IERC20(MC.YNETH).balanceOf(MC.YNETHX);
        emit Log("ynEthBal", ynEthBalance);

        // Test the processAccounting function
        vault.processAccounting();
        vm.stopPrank();

        uint256 newTotalAssets = vault.totalAssets();
        assertThreshold(newTotalAssets, totalAssets + assets, 2, "New total assets should equal deposit amount plus original total assets");
    }

    function assertThreshold(uint256 actual, uint256 expected, uint256 threshold, string memory errorMessage) internal pure {
        assertGt(actual, expected - threshold, string(abi.encodePacked(errorMessage, ": actual should be within the lower threshold of the expected value")));
        assertLt(actual, expected + threshold, string(abi.encodePacked(errorMessage, ": actual should be within the upper threshold of the expected value")));
    }

    function setWethWithdrawRule() internal {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        
        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.WETH, funcSig, rule);
    }    

    function setYnETHDepositETHRule() internal {
        bytes4 funcSig = bytes4(keccak256("depositETH(address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        address[] memory allowList = new address[](1);
        allowList[0] = MC.YNETHX; // receiver

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault.setProcessorRule(MC.YNETH, funcSig, rule);
    }
}
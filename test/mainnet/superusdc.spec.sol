// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISuperUSDC} from "src/interface/ISuperUSDC.sol";

contract SuperUSDCTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    BufferStrategy public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, bufferStrategy, provider) = BaseTest.deploy();
        vm.stopPrank();
    }
    
    function test_deposit_to_superusdc_vault() public {
        uint256 depositAmount = 10_000 * 1e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);
        
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();
        
        // Process accounting
        vault.processAccounting();
        
        // Record initial vault state
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 usdcBalanceBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 superUSDCBalanceBefore = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        
        depositToSuperUSDCVault(depositAmount);

        uint256 usdcBalanceAfter = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 superUSDCBalanceAfter = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        
        totalSupplyInvariant(vaultTotalSupplyBefore);
        totalAssetsInvariant(vaultAssetsBefore);
        
        assertTrue(superUSDCBalanceAfter > superUSDCBalanceBefore, "Vault should have SuperUSDC balance after deposit");
        console.log(superUSDCBalanceAfter);
        assertEq(
            usdcBalanceBefore - usdcBalanceAfter,
            depositAmount,
            "USDC balance should decrease by deposit amount"
        );
    }
    
    function test_deposit_and_withdraw_from_superusdc_vault() public {
        uint256 depositAmount = 10_000 * 1e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);
        
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();
        
        vault.processAccounting();
        
        uint256 vaultAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();
        uint256 superUSDCBalanceBefore = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        
        depositToSuperUSDCVault(depositAmount);
        
        uint256 superUSDCShares = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        assertTrue(superUSDCShares > 0, "Vault should have SuperUSDC shares after deposit");
        
        // Withdraw from SuperUSDC vault
        address[] memory withdrawTargets = new address[](1);
        uint256[] memory withdrawValues = new uint256[](1);
        bytes[] memory withdrawData = new bytes[](1);
        
        withdrawTargets[0] = MC.SUPER_USDC_VAULT;
        withdrawValues[0] = 0;
        withdrawData[0] = abi.encodeWithSignature("redeem(uint256,address,address,uint256)", superUSDCShares, address(vault), address(vault), 1);
        
        vm.startPrank(PROCESSOR);
        vault.processor(withdrawTargets, withdrawValues, withdrawData);
        vm.stopPrank();
        
        // Process accounting
        vault.processAccounting();
        
        uint256 superUSDCBalanceAfter = IERC20(MC.SUPER_USDC_VAULT).balanceOf(address(vault));
        
        totalSupplyInvariant(vaultTotalSupplyBefore);
        totalAssetsInvariant(vaultAssetsBefore);
        
        assertEq(superUSDCBalanceAfter, 0, "SuperUSDC balance should be 0 after full withdrawal");
    }
    

      function depositToSuperUSDCVault(uint256 depositAmount) internal {
        
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);
        
        targets[0] = MC.USDC;
        values[0] = 0;
        data[0] = abi.encodeCall(IERC20.approve, (MC.SUPER_USDC_VAULT, depositAmount));
        
        targets[1] = MC.SUPER_USDC_VAULT;
        values[1] = 0;
        data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));
        
        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();
        
        // Process accounting
        vault.processAccounting();
    }
}

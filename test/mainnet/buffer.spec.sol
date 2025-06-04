// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, Math, TimelockController} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseVault} from "src/BaseVault.sol";
import {IVault} from "src/interface/IVault.sol";
import {console} from "forge-std/console.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract VaultBufferInvariantsTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    BufferStrategy public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, bufferStrategy, provider) = BaseTest.deploy();
        // Process accounting to ensure vault is in sync
        vault.processAccounting();
        bufferStrategy.processAccounting();
    }

    function test_Strategy_ERC20_view_functions() public view {
        assertEq(
            bufferStrategy.name(), "Buffer Strategy YieldNest USD Max Vault", "Vault name should be 'Buffer Strategy YieldNest USD Max Vault'"
        );

        assertEq(bufferStrategy.symbol(), "Buffer Strategy ynUSDx", "Vault symbol should be 'Buffer Strategy ynUSDx'");

        assertEq(bufferStrategy.decimals(), 18, "Vault decimals should be 18");

        assertLe(
            bufferStrategy.totalSupply(),
            bufferStrategy.totalAssets(),
            "Vault totalSupply should be less than or equal to totalAssets"
        );
    }

    function test_Strategy_ERC4626_view_functions() public view {

        assertEq(address(bufferStrategy.asset()), MC.USDC, "Vault asset should be USDC");

        uint256 totalAssets = bufferStrategy.totalAssets();
        uint256 totalSupply = bufferStrategy.totalSupply();
        assertEq(totalAssets, 0, "TotalAssets should be 0");
        assertEq(totalSupply, 0, "TotalSupply should be 0");

        uint256 amount = 1e6;
        uint256 shares = bufferStrategy.convertToShares(amount);
        assertEq(shares, amount * 1e12, "Shares should be equal to amount deposited scaled by 1e12");

        uint256 convertedAssets = bufferStrategy.convertToAssets(shares);
        assertEq(convertedAssets, amount, "Converted assets should be equal to amount deposited");

        uint256 maxDeposit = bufferStrategy.maxDeposit(address(this));
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        uint256 maxMint = bufferStrategy.maxMint(address(this));
        assertGt(maxMint, 0, "Max mint should be greater than 0");

        uint256 maxWithdraw = bufferStrategy.maxWithdraw(address(this));
        assertEq(maxWithdraw, 0, "Max withdraw should be zero");

        uint256 maxRedeem = bufferStrategy.maxRedeem(address(this));
        assertEq(maxRedeem, 0, "Max redeem should be zero");
    }

    function test_buffer_strategy_view_functions() public view {
        assertFalse(bufferStrategy.paused(), "Vault should not be paused");

        address[] memory assets = bufferStrategy.getAssets();
        assertEq(assets.length, 3, "There should be one asset in the vault");
        assertEq(assets[0], address(wrappedUSDC), "First asset should be wrappedUSDC");
        assertEq(assets[1], MC.USDC, "Second asset should be USDC");

        assertEq(bufferStrategy.asset(), MC.USDC, "Vault asset should be USDC");
        assertEq(bufferStrategy.defaultAssetIndex(), 1, "Default asset index should be 1");
    }

    function allocateToBuffer(uint256 depositAmount) public returns (uint256 bufferStrategySharesMinted) {
        // Allocate to buffer (MorphoGauntletUSDC core vault)
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = MC.USDC;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(bufferStrategy), depositAmount));

            targets[1] = address(bufferStrategy);
            values[1] = 0;
            data[1] = abi.encodeCall(BaseVault.depositAsset, (MC.USDC, depositAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();

            bufferStrategySharesMinted = abi.decode(returnData[1], (uint256));
        }
        vault.processAccounting();
        bufferStrategy.processAccounting();
    }

    function test_allocate_to_buffer_strategy_with_sync_deposit_on(uint256 userDepositAmount, uint256 bufferDepositAmount) public {
        address alice = makeAddr("alice");
        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);
        bufferDepositAmount = bound(bufferDepositAmount, 1000, userDepositAmount);

        uint256 expectedSharesToReceive = vault.previewDeposit(userDepositAmount);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        vault.processAccounting();
        bufferStrategy.processAccounting();

        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());

        assertEq(expectedSharesToReceive, userDepositAmount * 1e12, "Shares should be equal to amount deposited scaled by 1e12");
        
        totalSupplyInvariant(totalSupplyBefore + expectedSharesToReceive);
        totalAssetsInvariant(totalAssetsBefore + userDepositAmount);
        assertEq(vault.totalBaseAssets(), userDepositAmount * 1e12, "Vault should have the same total base assets as the user deposit amount scaled by 1e12");


        totalAssetsBefore = vault.totalAssets();
        totalSupplyBefore = vault.totalSupply();

        uint256 bufferStrategySharesMinted;
        uint256 expectedShareBalanceOfMorphoGauntletUsdcVault;
        {
            // allocate to buffer
            uint256 usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
            uint256 usdcBalanceOfBufferBefore = IERC20(MC.USDC).balanceOf(vault.buffer());
            expectedShareBalanceOfMorphoGauntletUsdcVault = IERC4626(MC.MORPHO_GAUNTLET_USDC_VAULT).previewDeposit(bufferDepositAmount);

            bufferStrategySharesMinted = allocateToBuffer(bufferDepositAmount);

            uint256 usdcBalanceOfVaultAfter = IERC20(MC.USDC).balanceOf(address(vault));
            uint256 usdcBalanceOfBufferAfter = IERC20(MC.USDC).balanceOf(vault.buffer());
            assertEq(usdcBalanceOfVaultBefore - usdcBalanceOfVaultAfter, bufferDepositAmount, "USDC balance should decrease by amount deposited in buffer");
            assertEq(usdcBalanceOfBufferAfter, 0, "Buffer balance should be allocated to usdc core vault due to sync deposit on");
        }

        assertGt(bufferStrategySharesMinted, 0, "Buffer shares should be greater than 0");
        assertApproxEqAbs(bufferStrategy.totalAssets(), bufferDepositAmount, 1e6, "Buffer assets should equal buffer amount");
        assertEq(IERC20(MC.MORPHO_GAUNTLET_USDC_VAULT).balanceOf(address(bufferStrategy)), expectedShareBalanceOfMorphoGauntletUsdcVault, "Incorrect gauntlet usdc vault balance in buffer strategy");
        assertEq(bufferStrategy.balanceOf(address(vault)), bufferStrategySharesMinted, "Incorrect share amount of bufferStrategyShares in vault");
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, 1e7, "Vault total assets should be similar to before ignorning rounding errors");
        totalSupplyInvariant(totalSupplyBefore);
        
    }

    function test_allocateToBuffer_syncDeposit_off(uint256 userDepositAmount, uint256 bufferDepositAmount) public {
        vm.prank(DEPOSIT_MANAGER);
        bufferStrategy.setSyncDeposit(false);

        address alice = makeAddr("alice");

        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);
        bufferDepositAmount = bound(bufferDepositAmount, 1000, userDepositAmount);


        // Make initial deposit
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        // Process accounting
        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Allocate to buffer
        uint256 bufferStrategySharesMinted = allocateToBuffer(bufferDepositAmount);
        bufferStrategy.processAccounting();

        assertEq(IERC20(MC.USDC).balanceOf(vault.buffer()), bufferDepositAmount, "Buffer should have received USDC");
        assertEq(IERC20(MC.USDC).balanceOf(address(vault)), userDepositAmount - bufferDepositAmount, "Vault should have received USDC");
        assertEq(bufferStrategy.totalAssets(), bufferDepositAmount, "Buffer assets should equal buffer amount");
        assertEq(bufferStrategy.balanceOf(address(vault)), bufferStrategySharesMinted, "Incorrect share amount of bufferStrategyShares in vault");
        assertEq(bufferStrategy.totalSupply(), bufferStrategySharesMinted, "Buffer strategy total supply should equal buffer strategy shares minted");

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariant(initialAssets);
    }

    function testDonationToBuffer_withoutBufferAllocation(uint256 userDepositAmount, uint256 bufferDonationAmount) public {
        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);
        bufferDonationAmount = bound(bufferDonationAmount, 1000, userDepositAmount);

        address alice = makeAddr("alice");

        // Initial state
        uint256 initialSupply = vault.totalSupply();
        uint256 initialAssets = vault.totalAssets();

        uint256 expectedSharesToReceive = vault.previewDeposit(userDepositAmount);

        // Make initial deposit
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        // Process accounting
        vault.processAccounting();

        totalSupplyInvariant(initialSupply + expectedSharesToReceive);
        totalAssetsInvariant(initialAssets + userDepositAmount);

        initialSupply = vault.totalSupply();
        initialAssets = vault.totalAssets();

        allocateToBuffer(userDepositAmount);

        // Donate directly to buffer
        deal(MC.USDC, address(this), bufferDonationAmount);
        IERC20(MC.USDC).transfer(vault.buffer(), bufferDonationAmount);

        vault.processAccounting();
        bufferStrategy.processAccounting();

        totalSupplyInvariant(initialSupply);
        assertApproxEqAbs(vault.totalAssets(), initialAssets + bufferDonationAmount, 1e7, "Vault total assets should increase by buffer donation amount ignoring rounding errors");
    }

    function test_revert_nonAllocator_allocate_to_buffer() public {
        address alice = makeAddr("alice");
        uint256 amount = 1000e6;
        deal(MC.USDC, alice, amount);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, bufferStrategy.ALLOCATOR_ROLE()
            )
        );
        bufferStrategy.depositAsset(MC.USDC, amount, alice);

        deal(address(bufferStrategy), alice, amount);
        deal(MC.USDC, address(bufferStrategy), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, bufferStrategy.ALLOCATOR_ROLE()
            )
        );
        bufferStrategy.withdrawAsset(MC.USDC, 1, alice, alice);
        vm.stopPrank();

    }

    function test_withdrawFromBuffer_syncWithdraw_off(uint256 userDepositAmount) public {
        vm.prank(DEPOSIT_MANAGER);
        bufferStrategy.setSyncWithdraw(false);

        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        allocateToBuffer(userDepositAmount);

        uint256 vaultSharesOfAliceBefore = vault.balanceOf(alice);
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vm.startPrank(alice);
        vault.withdraw(maxWithdraw, alice, alice);
        vm.stopPrank();

        assertEq(IERC20(MC.USDC).balanceOf(alice), 0, "Alice should not receive USDC");
        assertEq(vault.balanceOf(alice), vaultSharesOfAliceBefore, "Alice should have same shares before");
        assertEq(maxWithdraw, 0, "Max withdraw should be 0 due to sync withdraw off and no usdc in buffer");

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, alice, maxWithdraw + 1, maxWithdraw));
        vm.stopPrank();

        // donate 1 usdc to buffer
        deal(MC.USDC, address(bufferStrategy), 1e6);
        vm.startPrank(alice);
        vault.withdraw(1e6, alice, alice);
        vm.stopPrank();

        assertEq(IERC20(MC.USDC).balanceOf(alice), 1e6, "Alice should receive 1 usdc");
        assertEq(IERC20(MC.USDC).balanceOf(address(bufferStrategy)), 0, "Buffer should have 0 usdc due to sync deposit off");
        assertLt(vault.balanceOf(alice), vaultSharesOfAliceBefore, "Alice should have less shares due to processing of withdraw");
    }

    function test_withdrawFromBuffer_syncWithdraw_on(uint256 userDepositAmount) public {
        vm.prank(DEPOSIT_MANAGER);
        bufferStrategy.setSyncWithdraw(true);

        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);
        address alice = makeAddr("alice");
        
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        allocateToBuffer(userDepositAmount);

        uint256 vaultSharesOfAliceBefore = vault.balanceOf(alice);
        uint256 withdrawableUSDC = vault.previewRedeem(vaultSharesOfAliceBefore);
        vm.startPrank(alice);
        vault.redeem(vaultSharesOfAliceBefore, alice, alice);
        vm.stopPrank();

        vault.processAccounting();
        bufferStrategy.processAccounting();

        assertEq(IERC20(MC.USDC).balanceOf(alice), withdrawableUSDC, "Alice should receive max withdraw amount");
        assertApproxEqAbs(IERC20(MC.USDC).balanceOf(alice), userDepositAmount, 1e7, "Alice should receive approximately same amount of usdc as deposited");
        assertGt(withdrawableUSDC, 0, "Max withdraw should be 0 due to sync withdraw off and no usdc in buffer");
        assertEq(vault.balanceOf(alice), 0, "Alice should have same shares before");
        assertEq(IERC20(MC.USDC).balanceOf(address(bufferStrategy)), 0, "Buffer should have 0 usdc due to sync deposit off");
        assertEq(vault.balanceOf(alice), 0, "Alice should have 0 shares due to processing of withdraw");
        assertEq(vault.totalSupply(), 0, "Vault total supply should be 0");
        assertApproxEqAbs(vault.totalAssets(), 0, 1e7, "Vault total assets should be 0");
        assertApproxEqAbs(bufferStrategy.totalSupply(), 0, 1e18, "Buffer strategy total supply should be 0");
        assertApproxEqAbs(bufferStrategy.totalAssets(), 0, 1e7, "Buffer strategy total assets should be 0");
    }

    function _depositAssetToVault(address asset, uint256 amount, address user) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(vault), amount);
        vault.depositAsset(asset, amount, user);
        vm.stopPrank();
    }
}

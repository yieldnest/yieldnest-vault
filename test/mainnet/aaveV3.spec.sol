// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "src/Common.sol";
import {IProvider, IAaveV3Pool, IAaveV3Oracle, IStETH} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {Provider} from "src/module/Provider.sol";
import {AaveV3Rules} from "script/rules/AaveV3Rules.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";

interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
}

interface IStETHSubmit {
    function submit(address _referral) external payable returns (uint256);
}

/**
 * @title AaveV3IntegrationTest
 * @notice Fork test for Aave V3 integration with ynETHx vault
 * @dev Tests supplying wstETH as collateral and borrowing USDC
 *
 * This test demonstrates:
 * 1. How to set up processor rules for Aave V3 operations
 * 2. How to supply collateral (wstETH) to Aave
 * 3. How to borrow assets (USDC) against collateral
 * 4. How to repay borrowed assets
 * 5. How to withdraw collateral
 * 6. How to track asset values correctly through the Provider
 */
contract AaveV3IntegrationTest is BaseIntegrationTest {
    IAaveV3Pool public aavePool;
    IAaveV3Oracle public aaveOracle;
    Provider public provider;

    function setUp() public override {
        super.setUp();

        aavePool = IAaveV3Pool(MC.AAVE_V3_POOL);
        aaveOracle = IAaveV3Oracle(MC.AAVE_V3_ORACLE);

        // Deploy new provider with aToken support
        provider = new Provider();

        // Setup: Grant roles and configure vault for Aave integration
        _setupVaultForAave();
    }

    /**
     * @notice Bootstrap the vault with wstETH by enabling deposits temporarily
     * @param amount The amount of wstETH to deposit into the vault
     */
    function _bootstrapVaultWithWstETH(uint256 amount) internal {
        address depositor = address(0xDE9051700);

        // Deal wstETH to the depositor
        deal(MC.WSTETH, depositor, amount);

        // Find wstETH index in the asset list
        address[] memory assets = vault.getAssets();
        uint256 wstEthIndex = type(uint256).max;
        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == MC.WSTETH) {
                wstEthIndex = i;
                break;
            }
        }
        require(wstEthIndex != type(uint256).max, "wstETH not found in asset list");

        // Temporarily enable wstETH deposits
        vm.startPrank(ADMIN);
        vault.updateAsset(wstEthIndex, IVault.AssetUpdateFields({active: true}));
        vm.stopPrank();

        // Deposit wstETH into the vault
        vm.startPrank(depositor);
        IERC20(MC.WSTETH).approve(address(vault), amount);
        vault.depositAsset(MC.WSTETH, amount, depositor);
        vm.stopPrank();

        // Disable wstETH deposits after bootstrapping
        vm.startPrank(ADMIN);
        vault.updateAsset(wstEthIndex, IVault.AssetUpdateFields({active: false}));
        vm.stopPrank();
    }

    /**
     * @notice Calculate safe borrow amount based on collateral
     * @param supplyAmount The amount of wstETH being supplied as collateral
     * @return borrowAmount The safe amount of USDC to borrow (30% of collateral value)
     */
    function _calculateBorrowAmount(uint256 supplyAmount) internal view returns (uint256) {
        // wstETH -> ETH rate
        uint256 wstEthToEthRate = IStETH(MC.STETH).getPooledEthByShares(1e18);
        // Rough ETH price in USD ($3000)
        uint256 collateralInUsd = (supplyAmount * wstEthToEthRate * 3000) / 1e36;
        // Borrow 30% of collateral value, in USDC (6 decimals)
        uint256 borrowAmount = (collateralInUsd * 30 / 100) * 1e6;
        // Minimum 10 USDC
        if (borrowAmount < 10e6) {
            borrowAmount = 10e6;
        }
        return borrowAmount;
    }

    function _setupVaultForAave() internal {
        vm.startPrank(ADMIN);

        // Grant necessary roles
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), ADMIN);
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);

        // Set the new provider
        vault.setProvider(address(provider));

        // Note: USDC is NOT added as a vault asset since we don't track it in the provider
        // The vault only tracks collateral (aWSTETH), not borrowed assets

        // Add aWSTETH as an asset for accounting
        if (!vault.hasAsset(MC.AAVE_A_WSTETH)) {
            vault.addAsset(MC.AAVE_A_WSTETH, true);
        }

        // Setup processor rules for Aave operations
        _setupAaveProcessorRules();

        vm.stopPrank();
    }

    function _setupAaveProcessorRules() internal {
        // 1. Approval rule for wstETH -> Aave Pool
        SafeRules.setProcessorRule(
            vault,
            BaseRules.getApprovalRule(MC.WSTETH, MC.AAVE_V3_POOL),
            true // force
        );

        // 2. Approval rule for USDC -> Aave Pool (for repayment)
        SafeRules.setProcessorRule(vault, BaseRules.getApprovalRule(MC.USDC, MC.AAVE_V3_POOL), true);

        // 3. Supply rule for wstETH
        SafeRules.setProcessorRule(vault, AaveV3Rules.getSupplyRule(MC.AAVE_V3_POOL, MC.WSTETH, MC.YNETHX), true);

        // 4. Withdraw rule for wstETH
        SafeRules.setProcessorRule(vault, AaveV3Rules.getWithdrawRule(MC.AAVE_V3_POOL, MC.WSTETH, MC.YNETHX), true);

        // 5. Borrow rule for USDC
        SafeRules.setProcessorRule(vault, AaveV3Rules.getBorrowRule(MC.AAVE_V3_POOL, MC.USDC, MC.YNETHX), true);

        // 6. Repay rule for USDC
        SafeRules.setProcessorRule(vault, AaveV3Rules.getRepayRule(MC.AAVE_V3_POOL, MC.USDC, MC.YNETHX), true);

        // 7. SetUserEMode rule (optional, for ETH-correlated assets)
        SafeRules.setProcessorRule(vault, AaveV3Rules.getSetUserEModeRule(MC.AAVE_V3_POOL), true);
    }

    /**
     * @notice Test that the provider correctly returns aWSTETH rate
     */
    function test_Provider_aWSTETHRate() public view {
        uint256 aWstEthRate = provider.getRate(MC.AAVE_A_WSTETH);
        uint256 wstEthRate = provider.getRate(MC.WSTETH);

        // aWSTETH should have the same rate as wstETH (1:1 underlying)
        assertEq(aWstEthRate, wstEthRate, "aWSTETH rate should equal wstETH rate");
    }

    /**
     * @notice Test supplying wstETH to Aave as collateral (fuzzed)
     * @dev Verifies processAccounting correctly updates TVL after supply
     * @param supplyAmount The fuzzed amount of wstETH to supply
     */
    function testFuzz_Aave_SupplyCollateral(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.1 ether, 100 ether);

        vault.processAccounting();

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        uint256 totalAssetsBefore = vault.totalAssets();

        // Supply wstETH to Aave
        _supplyToAave(MC.WSTETH, supplyAmount);

        uint256 vaultWstEthAfter = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        uint256 aTokenBalance = IERC20(MC.AAVE_A_WSTETH).balanceOf(MC.YNETHX);

        // wstETH should have left the vault
        assertEq(vaultWstEthAfter, vaultWstEthBefore - supplyAmount, "wstETH should be sent to Aave");

        // Vault should now have aTokens (allow for small rounding difference)
        assertApproxEqAbs(aTokenBalance, supplyAmount, 2, "Vault should receive aTokens");

        // Call processAccounting to update stored totalAssets
        vault.processAccounting();
        uint256 storedAfterProcess = vault.totalAssets();

        // Verify processAccounting updated the stored value correctly
        assertApproxEqAbs(
            storedAfterProcess,
            totalAssetsBefore,
            3, // Very tight threshold
            "processAccounting should update stored totalAssets"
        );
    }

    /**
     * @notice Test borrowing USDC against wstETH collateral (fuzzed)
     * @dev Verifies processAccounting correctly updates TVL after supply and borrow
     * @param supplyAmount The fuzzed amount of wstETH to supply as collateral
     */
    function testFuzz_Aave_BorrowUSDC(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.1 ether, 100 ether);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        // Get initial computed assets for comparison
        uint256 initialComputedAssets = vault.computeTotalAssets();

        // Use a relative threshold of 0.01% for large values
        uint256 threshold = initialComputedAssets / 10000;
        if (threshold < 1e15) threshold = 1e15;

        // First supply collateral
        _supplyToAave(MC.WSTETH, supplyAmount);

        // Verify processAccounting after supply
        uint256 computedAfterSupply = vault.computeTotalAssets();
        vault.processAccounting();
        uint256 storedAfterSupply = vault.totalAssets();

        assertApproxEqAbs(
            storedAfterSupply,
            computedAfterSupply,
            3,
            "processAccounting should update stored totalAssets after supply"
        );

        // Value should be preserved after supply
        assertEqThreshold(storedAfterSupply, initialComputedAssets, threshold, "Value should be preserved after supply");

        uint256 usdcBefore = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);

        // Borrow USDC
        _borrowFromAave(MC.USDC, borrowAmount);

        // Verify processAccounting after borrow
        uint256 computedAfterBorrow = vault.computeTotalAssets();
        vault.processAccounting();
        uint256 storedAfterBorrow = vault.totalAssets();

        assertApproxEqAbs(
            storedAfterBorrow,
            computedAfterBorrow,
            3,
            "processAccounting should update stored totalAssets after borrow"
        );

        // USDC not tracked, so assets should remain similar
        assertApproxEqAbs(
            storedAfterBorrow,
            storedAfterSupply,
            3,
            "Assets should remain similar after borrow (USDC not tracked)"
        );

        uint256 usdcAfter = IERC20(MC.USDC).balanceOf(MC.YNETHX);

        assertEq(usdcAfter, usdcBefore + borrowAmount, "Vault should receive borrowed USDC");

        // Check debt
        uint256 debtBalance = IERC20(MC.AAVE_VARIABLE_DEBT_USDC).balanceOf(MC.YNETHX);
        assertGe(debtBalance, borrowAmount, "Vault should have USDC debt");

        // Check health factor is still healthy
        (,,,,, uint256 healthFactor) = aavePool.getUserAccountData(MC.YNETHX);
        assertGt(healthFactor, 1e18, "Health factor should be > 1");
    }

    /**
     * @notice Test full cycle: supply, borrow, repay, withdraw (fuzzed)
     * @dev Verifies processAccounting at each step of the cycle
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_FullCycle(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.1 ether, 100 ether);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);


        // 1. Supply collateral
        _supplyToAave(MC.WSTETH, supplyAmount);
        vault.processAccounting();
        uint256 assetsAfterSupply = vault.totalAssets();

        // Value should be preserved after supply
        assertApproxEqAbs(assetsAfterSupply, initialTotalAssets, 3, "Value should be preserved after supply");

        // 2. Borrow USDC
        _borrowFromAave(MC.USDC, borrowAmount);
        vault.processAccounting();
        uint256 assetsAfterBorrow = vault.totalAssets();

        uint256 usdcBalance = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        assertEq(usdcBalance, borrowAmount, "Should have borrowed USDC");

        // USDC not tracked, so assets should remain similar
        assertApproxEqAbs(assetsAfterBorrow, assetsAfterSupply, 3, "Assets should remain similar after borrow");

        // 3. Repay USDC (use type(uint256).max for full repayment including accrued interest)
        // Need to give vault extra USDC to cover any accrued interest
        deal(MC.USDC, MC.YNETHX, borrowAmount + 1000e6); // Extra 1000 USDC for interest buffer
        _repayToAave(MC.USDC, type(uint256).max);
        vault.processAccounting();

        uint256 debtAfterRepay = IERC20(MC.AAVE_VARIABLE_DEBT_USDC).balanceOf(MC.YNETHX);
        assertEq(debtAfterRepay, 0, "Debt should be zero after full repay");

        // 4. Withdraw collateral (use type(uint256).max to withdraw all)
        _withdrawFromAave(MC.WSTETH, type(uint256).max);
        vault.processAccounting();
        uint256 assetsAfterWithdraw = vault.totalAssets();

        uint256 wstEthAfter = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);

        // Should have gotten back approximately the same amount (minus any rounding)
        assertGe(wstEthAfter, vaultWstEthBefore - 10, "Should have withdrawn wstETH back");

        // Final assets should be close to initial (full cycle complete)
        assertApproxEqAbs(
            assetsAfterWithdraw, initialTotalAssets, 3, "Final assets should match initial after full cycle"
        );

        // Check Aave position is closed
        (uint256 totalCollateral, uint256 totalDebt,,,,) = aavePool.getUserAccountData(MC.YNETHX);

        assertEq(totalCollateral, 0, "Collateral should be zero");
    }

    /**
     * @notice Test that accounting correctly tracks value with Aave position (fuzzed)
     * @dev Verifies processAccounting updates totalAssets correctly after Aave operations
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_AccountingCorrectness(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.1 ether, 100 ether);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);

        // Get initial state - totalAssets() returns stored value, computeTotalAssets() calculates fresh
        uint256 initialComputedAssets = vault.computeTotalAssets();

        // Use a relative threshold of 0.01% for large values
        uint256 threshold = initialComputedAssets / 10000; // 0.01%
        if (threshold < 1e15) threshold = 1e15;

        // Supply to Aave
        _supplyToAave(MC.WSTETH, supplyAmount);

        // Before processAccounting, stored value is stale
        uint256 computedAfterSupply = vault.computeTotalAssets();

        // Call processAccounting to update stored totalAssets
        vault.processAccounting();

        // After processAccounting, stored should match computed
        uint256 storedAfterProcess = vault.totalAssets();

        // Verify processAccounting updated the stored value correctly
        assertEqThreshold(
            storedAfterProcess,
            computedAfterSupply,
            1e10, // Very tight threshold - should be nearly exact
            "processAccounting should update stored totalAssets to match computed"
        );

        // Value should be preserved (wstETH -> aWSTETH)
        assertEqThreshold(
            storedAfterProcess, initialComputedAssets, threshold, "Value should be preserved after Aave supply"
        );

        // Borrow USDC
        _borrowFromAave(MC.USDC, borrowAmount);
        uint256 computedAfterBorrow = vault.computeTotalAssets();

        // Process accounting again after borrow
        vault.processAccounting();
        uint256 storedAfterBorrow = vault.totalAssets();

        // Verify processAccounting updated correctly after borrow
        assertEqThreshold(
            storedAfterBorrow,
            computedAfterBorrow,
            1e10,
            "processAccounting should update stored totalAssets after borrow"
        );

        // Note: USDC is not tracked in the provider, so total assets won't reflect borrowed USDC
        // The vault tracks collateral (aWSTETH) but not the borrowed USDC value
        // Total assets should remain roughly the same (only aWSTETH is tracked)
        assertEqThreshold(
            storedAfterBorrow, storedAfterProcess, threshold, "Total assets should remain similar (USDC not tracked)"
        );
    }

    /**
     * @notice Test processor rules are enforced (fuzzed)
     * @dev Verifies processAccounting state is unchanged after failed operation
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_UnauthorizedCallReverts(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.1 ether, 100 ether);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        // Record state before failed operation
        vault.processAccounting();
        uint256 storedBefore = vault.totalAssets();
        uint256 computedBefore = vault.computeTotalAssets();

        // Try to supply to an unauthorized address (should revert)
        address unauthorizedReceiver = address(0xdead);

        address[] memory targets = new address[](2);
        targets[0] = MC.WSTETH;
        targets[1] = MC.AAVE_V3_POOL;

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.AAVE_V3_POOL, supplyAmount);
        // Try to supply on behalf of unauthorized address
        data[1] = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)", MC.WSTETH, supplyAmount, unauthorizedReceiver, 0
        );

        vm.startPrank(PROCESSOR);
        vm.expectRevert(); // Should revert due to address not in allowlist
        vault.processor(targets, values, data);
        vm.stopPrank();

        // Verify state unchanged after failed operation
        vault.processAccounting();
        uint256 storedAfter = vault.totalAssets();
        uint256 computedAfter = vault.computeTotalAssets();

        assertEq(storedAfter, storedBefore, "Stored totalAssets should be unchanged after failed operation");
        assertEq(computedAfter, computedBefore, "Computed totalAssets should be unchanged after failed operation");
    }

    /**
     * @notice Test full borrow and transfer flow: deposit wstETH, borrow USDC, transfer USDC out
     * @dev Verifies processAccounting at each step and demonstrates transfer rule usage
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_BorrowAndTransferOut(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, 0.1 ether, 100 ether);

        // Designated recipient for USDC transfer
        address usdcRecipient = address(0xBEEF);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        // Get initial state
        uint256 initialComputedAssets = vault.computeTotalAssets();

        // Setup transfer rule for USDC to recipient
        vm.startPrank(ADMIN);
        SafeRules.setProcessorRule(vault, BaseRules.getTransferRule(MC.USDC, usdcRecipient), true);
        vm.stopPrank();

        // Verify transfer rule is active
        IVault.FunctionRule memory transferRule =
            vault.getProcessorRule(MC.USDC, bytes4(keccak256("transfer(address,uint256)")));
        assertTrue(transferRule.isActive, "USDC transfer rule should be active");

        // 1. Supply wstETH to Aave as collateral
        _supplyToAave(MC.WSTETH, supplyAmount);
        vault.processAccounting();
        uint256 assetsAfterSupply = vault.totalAssets();

        // Value should be preserved after supply
        assertApproxEqAbs(assetsAfterSupply, initialComputedAssets, 4, "Value should be preserved after supply");

        // 2. Borrow USDC against collateral
        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);
        _borrowFromAave(MC.USDC, borrowAmount);
        vault.processAccounting();
        uint256 assetsAfterBorrow = vault.totalAssets();

        // Verify vault received USDC
        uint256 vaultUsdcBalance = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        assertEq(vaultUsdcBalance, borrowAmount, "Vault should have borrowed USDC");

        // USDC not tracked, so assets should remain similar
        assertApproxEqAbs(assetsAfterBorrow, assetsAfterSupply, 3, "Assets should remain similar after borrow");

        // 3. Transfer USDC out to designated recipient
        uint256 recipientBalanceBefore = IERC20(MC.USDC).balanceOf(usdcRecipient);
        _transferToken(MC.USDC, usdcRecipient, borrowAmount);
        vault.processAccounting();
        uint256 assetsAfterTransfer = vault.totalAssets();

        // Verify USDC was transferred
        uint256 vaultUsdcAfterTransfer = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        uint256 recipientBalanceAfter = IERC20(MC.USDC).balanceOf(usdcRecipient);

        assertEq(vaultUsdcAfterTransfer, 0, "Vault should have no USDC after transfer");
        assertEq(
            recipientBalanceAfter, recipientBalanceBefore + borrowAmount, "Recipient should have received borrowed USDC"
        );

        // USDC not tracked, so assets should remain similar after transfer
        assertApproxEqAbs(assetsAfterTransfer, assetsAfterBorrow, 3, "Assets should remain similar after transfer");

        // Verify Aave position still exists
        (uint256 totalCollateral, uint256 totalDebt,,,,) = aavePool.getUserAccountData(MC.YNETHX);
        assertGt(totalCollateral, 0, "Should still have collateral in Aave");
        assertGt(totalDebt, 0, "Should still have debt in Aave");

        // Verify health factor is still healthy
        (,,,,, uint256 healthFactor) = aavePool.getUserAccountData(MC.YNETHX);
        assertGt(healthFactor, 1e18, "Health factor should be > 1");
    }

    /**
     * @notice Test setting up all required rules for Aave integration
     * @dev This documents all the rules needed
     */
    function test_Aave_RequiredRulesDocumentation() public view {
        // Document all required rules for Aave integration:

        // 1. wstETH approval to Aave Pool
        IVault.FunctionRule memory approveRule =
            vault.getProcessorRule(MC.WSTETH, bytes4(keccak256("approve(address,uint256)")));
        assertTrue(approveRule.isActive, "wstETH approve rule should be active");

        // 2. USDC approval to Aave Pool (for repayment)
        IVault.FunctionRule memory usdcApproveRule =
            vault.getProcessorRule(MC.USDC, bytes4(keccak256("approve(address,uint256)")));
        assertTrue(usdcApproveRule.isActive, "USDC approve rule should be active");

        // 3. Aave supply rule
        IVault.FunctionRule memory supplyRule =
            vault.getProcessorRule(MC.AAVE_V3_POOL, bytes4(keccak256("supply(address,uint256,address,uint16)")));
        assertTrue(supplyRule.isActive, "Aave supply rule should be active");

        // 4. Aave withdraw rule
        IVault.FunctionRule memory withdrawRule =
            vault.getProcessorRule(MC.AAVE_V3_POOL, bytes4(keccak256("withdraw(address,uint256,address)")));
        assertTrue(withdrawRule.isActive, "Aave withdraw rule should be active");

        // 5. Aave borrow rule
        IVault.FunctionRule memory borrowRule =
            vault.getProcessorRule(MC.AAVE_V3_POOL, bytes4(keccak256("borrow(address,uint256,uint256,uint16,address)")));
        assertTrue(borrowRule.isActive, "Aave borrow rule should be active");

        // 6. Aave repay rule
        IVault.FunctionRule memory repayRule =
            vault.getProcessorRule(MC.AAVE_V3_POOL, bytes4(keccak256("repay(address,uint256,uint256,address)")));
        assertTrue(repayRule.isActive, "Aave repay rule should be active");
    }

    // ============ Helper Functions ============

    function _supplyToAave(address asset, uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = asset;
        targets[1] = MC.AAVE_V3_POOL;

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.AAVE_V3_POOL, amount);
        data[1] = abi.encodeWithSignature("supply(address,uint256,address,uint16)", asset, amount, MC.YNETHX, 0);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function _withdrawFromAave(address asset, uint256 amount) internal {
        address[] memory targets = new address[](1);
        targets[0] = MC.AAVE_V3_POOL;

        uint256[] memory values = new uint256[](1);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("withdraw(address,uint256,address)", asset, amount, MC.YNETHX);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function _borrowFromAave(address asset, uint256 amount) internal {
        address[] memory targets = new address[](1);
        targets[0] = MC.AAVE_V3_POOL;

        uint256[] memory values = new uint256[](1);

        bytes[] memory data = new bytes[](1);
        // interestRateMode: 2 = variable rate
        data[0] =
            abi.encodeWithSignature("borrow(address,uint256,uint256,uint16,address)", asset, amount, 2, 0, MC.YNETHX);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function _repayToAave(address asset, uint256 amount) internal {
        address[] memory targets = new address[](2);
        targets[0] = asset;
        targets[1] = MC.AAVE_V3_POOL;

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.AAVE_V3_POOL, amount);
        // interestRateMode: 2 = variable rate
        data[1] = abi.encodeWithSignature("repay(address,uint256,uint256,address)", asset, amount, 2, MC.YNETHX);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function _transferToken(address token, address recipient, uint256 amount) internal {
        address[] memory targets = new address[](1);
        targets[0] = token;

        uint256[] memory values = new uint256[](1);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("transfer(address,uint256)", recipient, amount);

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }
}

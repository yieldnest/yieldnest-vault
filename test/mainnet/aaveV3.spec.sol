// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {console2} from "lib/forge-std/src/console2.sol";
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

    // Fuzz bounds for wstETH supply amount
    uint256 constant MIN_SUPPLY = 0.1 ether;
    uint256 constant MAX_SUPPLY = 100 ether;

    event Log(string message, uint256 value);
    event LogAddress(string message, address value);

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
     * @notice Bootstrap the vault with wstETH by directly dealing to the vault
     * @param amount The amount of wstETH to add to the vault
     */
    function _bootstrapVaultWithWstETH(uint256 amount) internal {
        // Directly deal wstETH to the vault
        deal(MC.WSTETH, MC.YNETHX, amount);
        console2.log("Bootstrapped vault with wstETH:", amount);
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
            vault, BaseRules.getApprovalRule(MC.WSTETH, MC.AAVE_V3_POOL), true // force
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

        console2.log("aWSTETH rate:", aWstEthRate);
        console2.log("wstETH rate:", wstEthRate);

        // aWSTETH should have the same rate as wstETH (1:1 underlying)
        assertEq(aWstEthRate, wstEthRate, "aWSTETH rate should equal wstETH rate");
    }

    /**
     * @notice Test supplying wstETH to Aave as collateral (fuzzed)
     * @param supplyAmount The fuzzed amount of wstETH to supply
     */
    function testFuzz_Aave_SupplyCollateral(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, MIN_SUPPLY, MAX_SUPPLY);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        // Use computeTotalAssets since deal() doesn't update internal accounting
        uint256 totalAssetsBefore = vault.computeTotalAssets();

        console2.log("Vault wstETH before supply:", vaultWstEthBefore);
        console2.log("Total assets before supply:", totalAssetsBefore);
        console2.log("Supply amount:", supplyAmount);

        // Supply wstETH to Aave
        _supplyToAave(MC.WSTETH, supplyAmount);

        uint256 vaultWstEthAfter = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        uint256 aTokenBalance = IERC20(MC.AAVE_A_WSTETH).balanceOf(MC.YNETHX);

        console2.log("Vault wstETH after supply:", vaultWstEthAfter);
        console2.log("Vault aWSTETH balance:", aTokenBalance);

        // wstETH should have left the vault
        assertEq(vaultWstEthAfter, vaultWstEthBefore - supplyAmount, "wstETH should be sent to Aave");

        // Vault should now have aTokens (allow for small rounding difference)
        assertGe(aTokenBalance, supplyAmount - 2, "Vault should receive aTokens");

        // Compute total assets (wstETH -> aWSTETH should be value neutral)
        uint256 computedTotalAssets = vault.computeTotalAssets();
        console2.log("Computed total assets after supply:", computedTotalAssets);

        // Total assets should remain roughly the same (wstETH -> aWSTETH, same rate)
        // Use a relative threshold of 0.01% for large values
        uint256 threshold = totalAssetsBefore / 10000; // 0.01%
        if (threshold < 1e15) threshold = 1e15;
        assertEqThreshold(
            computedTotalAssets, totalAssetsBefore, threshold, "Total assets should remain similar after supply"
        );
    }

    /**
     * @notice Test borrowing USDC against wstETH collateral (fuzzed)
     * @param supplyAmount The fuzzed amount of wstETH to supply as collateral
     */
    function testFuzz_Aave_BorrowUSDC(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, MIN_SUPPLY, MAX_SUPPLY);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        // First supply collateral
        _supplyToAave(MC.WSTETH, supplyAmount);

        uint256 totalAssetsBefore = vault.computeTotalAssets();
        uint256 usdcBefore = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);

        console2.log("Computed total assets before borrow:", totalAssetsBefore);
        console2.log("USDC balance before borrow:", usdcBefore);
        console2.log("Borrow amount:", borrowAmount);

        // Get Aave account data before borrow
        (uint256 totalCollateral,, uint256 availableBorrow,,, uint256 healthFactor) =
            aavePool.getUserAccountData(MC.YNETHX);

        console2.log("Aave total collateral (USD, 8 decimals):", totalCollateral);
        console2.log("Aave available borrow (USD, 8 decimals):", availableBorrow);
        console2.log("Aave health factor before:", healthFactor);

        // Borrow USDC
        _borrowFromAave(MC.USDC, borrowAmount);

        uint256 usdcAfter = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        console2.log("USDC balance after borrow:", usdcAfter);

        assertEq(usdcAfter, usdcBefore + borrowAmount, "Vault should receive borrowed USDC");

        // Check debt
        uint256 debtBalance = IERC20(MC.AAVE_VARIABLE_DEBT_USDC).balanceOf(MC.YNETHX);
        console2.log("Variable debt USDC balance:", debtBalance);
        assertGe(debtBalance, borrowAmount, "Vault should have USDC debt");

        // Compute total assets after borrow
        uint256 totalAssetsAfter = vault.computeTotalAssets();
        console2.log("Computed total assets after borrow:", totalAssetsAfter);

        // Note: USDC is not tracked in the provider, so total assets won't reflect borrowed USDC
        // The vault tracks collateral (aWSTETH) but not the borrowed USDC value

        // Check health factor is still healthy
        (,,,,, healthFactor) = aavePool.getUserAccountData(MC.YNETHX);
        console2.log("Aave health factor after borrow:", healthFactor);
        assertGt(healthFactor, 1e18, "Health factor should be > 1");
    }

    /**
     * @notice Test full cycle: supply, borrow, repay, withdraw (fuzzed)
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_FullCycle(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, MIN_SUPPLY, MAX_SUPPLY);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);

        console2.log("Starting full cycle test");
        console2.log("Initial wstETH balance:", vaultWstEthBefore);
        console2.log("Supply amount:", supplyAmount);

        // 1. Supply collateral
        _supplyToAave(MC.WSTETH, supplyAmount);
        console2.log("Step 1: Supplied collateral");

        uint256 aTokenAfterSupply = IERC20(MC.AAVE_A_WSTETH).balanceOf(MC.YNETHX);
        console2.log("aToken balance after supply:", aTokenAfterSupply);

        // 2. Borrow USDC
        _borrowFromAave(MC.USDC, borrowAmount);
        console2.log("Step 2: Borrowed USDC");

        uint256 usdcBalance = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        assertEq(usdcBalance, borrowAmount, "Should have borrowed USDC");

        // 3. Repay USDC (use type(uint256).max for full repayment including accrued interest)
        // Need to give vault extra USDC to cover any accrued interest
        deal(MC.USDC, MC.YNETHX, borrowAmount + 1000e6); // Extra 1000 USDC for interest buffer
        _repayToAave(MC.USDC, type(uint256).max);
        console2.log("Step 3: Repaid USDC (full)");

        uint256 debtAfterRepay = IERC20(MC.AAVE_VARIABLE_DEBT_USDC).balanceOf(MC.YNETHX);
        console2.log("Debt after repay:", debtAfterRepay);
        assertEq(debtAfterRepay, 0, "Debt should be zero after full repay");

        // 4. Withdraw collateral (use type(uint256).max to withdraw all)
        uint256 aTokenBalance = IERC20(MC.AAVE_A_WSTETH).balanceOf(MC.YNETHX);
        console2.log("aToken balance before withdraw:", aTokenBalance);

        _withdrawFromAave(MC.WSTETH, type(uint256).max);
        console2.log("Step 4: Withdrew collateral");

        uint256 wstEthAfter = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        console2.log("wstETH after withdraw:", wstEthAfter);

        // Should have gotten back approximately the same amount (minus any rounding)
        assertGe(wstEthAfter, vaultWstEthBefore - 10, "Should have withdrawn wstETH back");

        // Check Aave position is closed
        (uint256 totalCollateral, uint256 totalDebt,,,,) = aavePool.getUserAccountData(MC.YNETHX);
        console2.log("Final Aave collateral:", totalCollateral);
        console2.log("Final Aave debt:", totalDebt);

        assertEq(totalCollateral, 0, "Collateral should be zero");
    }

    /**
     * @notice Test that accounting correctly tracks value with Aave position (fuzzed)
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_AccountingCorrectness(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, MIN_SUPPLY, MAX_SUPPLY);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

        uint256 borrowAmount = _calculateBorrowAmount(supplyAmount);

        // Get initial state using computeTotalAssets (not processAccounting)
        uint256 initialTotalAssets = vault.computeTotalAssets();
        console2.log("Initial computed total assets:", initialTotalAssets);

        // Supply to Aave
        _supplyToAave(MC.WSTETH, supplyAmount);
        uint256 afterAaveSupply = vault.computeTotalAssets();
        console2.log("After Aave supply:", afterAaveSupply);

        // Value should be preserved (wstETH -> aWSTETH)
        // Use a relative threshold of 0.01% for large values
        uint256 threshold = initialTotalAssets / 10000; // 0.01%
        if (threshold < 1e15) threshold = 1e15;
        assertEqThreshold(afterAaveSupply, initialTotalAssets, threshold, "Value should be preserved after Aave supply");

        // Borrow USDC
        _borrowFromAave(MC.USDC, borrowAmount);
        uint256 afterBorrow = vault.computeTotalAssets();
        console2.log("After USDC borrow:", afterBorrow);

        // Note: USDC is not tracked in the provider, so total assets won't reflect borrowed USDC
        // The vault tracks collateral (aWSTETH) but not the borrowed USDC value
        // Total assets should remain roughly the same (only aWSTETH is tracked)
        assertEqThreshold(afterBorrow, afterAaveSupply, threshold, "Total assets should remain similar (USDC not tracked)");
    }

    /**
     * @notice Test processor rules are enforced (fuzzed)
     * @param supplyAmount The fuzzed amount of wstETH to use
     */
    function testFuzz_Aave_UnauthorizedCallReverts(uint256 supplyAmount) public {
        supplyAmount = bound(supplyAmount, MIN_SUPPLY, MAX_SUPPLY);

        // Bootstrap vault with wstETH
        _bootstrapVaultWithWstETH(supplyAmount);

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

        console2.log("All required Aave rules are configured correctly");
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
}

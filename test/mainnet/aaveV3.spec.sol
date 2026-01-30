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

    // Use smaller amounts from existing vault balance
    uint256 public SUPPLY_AMOUNT;
    uint256 public BORROW_AMOUNT; // Will be calculated based on collateral

    event Log(string message, uint256 value);
    event LogAddress(string message, address value);

    function setUp() public override {
        super.setUp();

        aavePool = IAaveV3Pool(MC.AAVE_V3_POOL);
        aaveOracle = IAaveV3Oracle(MC.AAVE_V3_ORACLE);

        // Deploy new provider with USDC and aToken support
        provider = new Provider();

        // Use existing vault wstETH balance (use a small portion)
        uint256 vaultWstEth = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        console2.log("Vault existing wstETH balance:", vaultWstEth);

        // Use the full wstETH balance available (or cap at 1 ether for safety)
        SUPPLY_AMOUNT = vaultWstEth > 1 ether ? 1 ether : vaultWstEth;
        if (SUPPLY_AMOUNT < 0.01 ether) {
            revert("Vault needs at least 0.01 wstETH for tests");
        }

        // Calculate safe borrow amount (roughly 30% of collateral value in USDC)
        // wstETH ~= 1.22 ETH, ETH ~= $3000, so 0.1 wstETH ~= $366
        // Borrow ~30% = ~$100 = 100 USDC
        uint256 wstEthToEthRate = IStETH(MC.STETH).getPooledEthByShares(1e18);
        uint256 collateralInUsd = (SUPPLY_AMOUNT * wstEthToEthRate * 3000) / 1e36; // rough ETH price
        BORROW_AMOUNT = (collateralInUsd * 30 / 100) * 1e6; // 30% of collateral, in USDC (6 decimals)
        if (BORROW_AMOUNT < 10e6) {
            BORROW_AMOUNT = 10e6; // minimum 10 USDC
        }
        console2.log("Calculated borrow amount (USDC):", BORROW_AMOUNT);

        // Setup: Grant roles and configure vault for Aave integration
        _setupVaultForAave();
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
     * @notice Test supplying wstETH to Aave as collateral
     * @dev Uses existing vault wstETH balance
     */
    function test_Aave_SupplyCollateral() public {
        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        require(vaultWstEthBefore >= SUPPLY_AMOUNT, "Vault needs wstETH balance");

        uint256 totalAssetsBefore = vault.totalAssets();

        console2.log("Vault wstETH before supply:", vaultWstEthBefore);
        console2.log("Total assets before supply:", totalAssetsBefore);
        console2.log("Supply amount:", SUPPLY_AMOUNT);

        // Supply wstETH to Aave
        _supplyToAave(MC.WSTETH, SUPPLY_AMOUNT);

        uint256 vaultWstEthAfter = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        uint256 aTokenBalance = IERC20(MC.AAVE_A_WSTETH).balanceOf(MC.YNETHX);

        console2.log("Vault wstETH after supply:", vaultWstEthAfter);
        console2.log("Vault aWSTETH balance:", aTokenBalance);

        // wstETH should have left the vault
        assertEq(vaultWstEthAfter, vaultWstEthBefore - SUPPLY_AMOUNT, "wstETH should be sent to Aave");

        // Vault should now have aTokens
        assertGe(aTokenBalance, SUPPLY_AMOUNT - 1, "Vault should receive aTokens");

        // Compute total assets (wstETH -> aWSTETH should be value neutral)
        uint256 computedTotalAssets = vault.computeTotalAssets();
        console2.log("Computed total assets after supply:", computedTotalAssets);

        // Total assets should remain roughly the same (wstETH -> aWSTETH, same rate)
        assertEqThreshold(
            computedTotalAssets, totalAssetsBefore, 1e15, "Total assets should remain similar after supply"
        );
    }

    /**
     * @notice Test borrowing USDC against wstETH collateral
     */
    function test_Aave_BorrowUSDC() public {
        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        require(vaultWstEthBefore >= SUPPLY_AMOUNT, "Vault needs wstETH balance");

        // First supply collateral
        _supplyToAave(MC.WSTETH, SUPPLY_AMOUNT);

        uint256 totalAssetsBefore = vault.computeTotalAssets();
        uint256 usdcBefore = IERC20(MC.USDC).balanceOf(MC.YNETHX);

        console2.log("Computed total assets before borrow:", totalAssetsBefore);
        console2.log("USDC balance before borrow:", usdcBefore);

        // Get Aave account data before borrow
        (uint256 totalCollateral, uint256 totalDebt, uint256 availableBorrow,,, uint256 healthFactor) =
            aavePool.getUserAccountData(MC.YNETHX);

        console2.log("Aave total collateral (USD, 8 decimals):", totalCollateral);
        console2.log("Aave available borrow (USD, 8 decimals):", availableBorrow);
        console2.log("Aave health factor before:", healthFactor);

        // Borrow USDC
        _borrowFromAave(MC.USDC, BORROW_AMOUNT);

        uint256 usdcAfter = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        console2.log("USDC balance after borrow:", usdcAfter);

        assertEq(usdcAfter, usdcBefore + BORROW_AMOUNT, "Vault should receive borrowed USDC");

        // Check debt
        uint256 debtBalance = IERC20(MC.AAVE_VARIABLE_DEBT_USDC).balanceOf(MC.YNETHX);
        console2.log("Variable debt USDC balance:", debtBalance);
        assertGe(debtBalance, BORROW_AMOUNT, "Vault should have USDC debt");

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
     * @notice Test full cycle: supply, borrow, repay, withdraw
     */
    function test_Aave_FullCycle() public {
        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        require(vaultWstEthBefore >= SUPPLY_AMOUNT, "Vault needs wstETH balance");

        console2.log("Starting full cycle test");
        console2.log("Initial wstETH balance:", vaultWstEthBefore);
        console2.log("Supply amount:", SUPPLY_AMOUNT);

        // 1. Supply collateral
        _supplyToAave(MC.WSTETH, SUPPLY_AMOUNT);
        console2.log("Step 1: Supplied collateral");

        uint256 aTokenAfterSupply = IERC20(MC.AAVE_A_WSTETH).balanceOf(MC.YNETHX);
        console2.log("aToken balance after supply:", aTokenAfterSupply);

        // 2. Borrow USDC
        _borrowFromAave(MC.USDC, BORROW_AMOUNT);
        console2.log("Step 2: Borrowed USDC");

        uint256 usdcBalance = IERC20(MC.USDC).balanceOf(MC.YNETHX);
        assertEq(usdcBalance, BORROW_AMOUNT, "Should have borrowed USDC");

        // 3. Repay USDC (use type(uint256).max for full repayment including accrued interest)
        // Need to give vault extra USDC to cover any accrued interest
        deal(MC.USDC, MC.YNETHX, BORROW_AMOUNT + 1000e6); // Extra 1000 USDC for interest buffer
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
     * @notice Test that accounting correctly tracks value with Aave position
     */
    function test_Aave_AccountingCorrectness() public {
        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        require(vaultWstEthBefore >= SUPPLY_AMOUNT, "Vault needs wstETH balance");

        // Get initial state using computeTotalAssets (not processAccounting)
        uint256 initialTotalAssets = vault.computeTotalAssets();
        console2.log("Initial computed total assets:", initialTotalAssets);

        // Supply to Aave
        _supplyToAave(MC.WSTETH, SUPPLY_AMOUNT);
        uint256 afterAaveSupply = vault.computeTotalAssets();
        console2.log("After Aave supply:", afterAaveSupply);

        // Value should be preserved (wstETH -> aWSTETH)
        assertEqThreshold(afterAaveSupply, initialTotalAssets, 1e15, "Value should be preserved after Aave supply");

        // Borrow USDC
        _borrowFromAave(MC.USDC, BORROW_AMOUNT);
        uint256 afterBorrow = vault.computeTotalAssets();
        console2.log("After USDC borrow:", afterBorrow);

        // Note: USDC is not tracked in the provider, so total assets won't reflect borrowed USDC
        // The vault tracks collateral (aWSTETH) but not the borrowed USDC value
        // Total assets should remain roughly the same (only aWSTETH is tracked)
        assertEqThreshold(afterBorrow, afterAaveSupply, 1e15, "Total assets should remain similar (USDC not tracked)");
    }

    /**
     * @notice Test processor rules are enforced
     */
    function test_Aave_UnauthorizedCallReverts() public {
        uint256 vaultWstEthBefore = IERC20(MC.WSTETH).balanceOf(MC.YNETHX);
        require(vaultWstEthBefore >= SUPPLY_AMOUNT, "Vault needs wstETH balance");

        // Try to supply to an unauthorized address (should revert)
        address unauthorizedReceiver = address(0xdead);

        address[] memory targets = new address[](2);
        targets[0] = MC.WSTETH;
        targets[1] = MC.AAVE_V3_POOL;

        uint256[] memory values = new uint256[](2);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", MC.AAVE_V3_POOL, SUPPLY_AMOUNT);
        // Try to supply on behalf of unauthorized address
        data[1] = abi.encodeWithSignature(
            "supply(address,uint256,address,uint16)", MC.WSTETH, SUPPLY_AMOUNT, unauthorizedReceiver, 0
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

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, Math} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {HooksUtils} from "test/utils/HooksUtils.sol";

contract VaultBufferInvariantsTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function totalSupplyInvariant(uint256 supply) public view {
        uint256 finalVaultTotalSupply = vault.totalSupply();
        assertEqThreshold(
            supply, finalVaultTotalSupply, 3, "Vault totalSupply should be original totalSupply plus additional"
        );
    }

    function totalAssetsInvariant(uint256 assets) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertEqThreshold(
            assets, finalVaultTotalAssets, 3, "Vault totalAssets should be original totalAssets plus additional"
        );
    }

    function allocateToBuffer(uint256 amount) public returns (uint256 bufferShares) {
        bufferShares = ProcessorUtils.allocateToBuffer(vault, amount, PROCESSOR);
    }

    function test_Vault_4626Invariants_depositBase_WithBufferAllocation(uint256 assets, uint256 bufferAmount) public {
        vm.assume(assets > 1000_000);
        vm.assume(assets < 10_000 ether);
        vm.assume(bufferAmount < assets);
        vm.assume(bufferAmount > 1000_000);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Decimals should be 18");

        // Test the asset function
        assertEq(vault.asset(), MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        assertGt(vault.totalAssets(), 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        uint256 convertedAssets = vault.convertToAssets(shares);
        assertEqThreshold(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        uint256 previewedShares = vault.previewDeposit(assets);
        assertEqThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEqThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        {
            // Test the depositAsset function
            deal(address(this), assets);
            (bool success,) = MC.WETH.call{value: assets}("");
            assertTrue(success, "Weth deposit failed");
            IERC20(MC.WETH).approve(address(vault), assets);

            address receiver = address(this);
            uint256 depositedShares = vault.deposit(assets, receiver);
            assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");
        }

        vault.processAccounting();

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        uint256 bufferShares;
        {
            // allocate to buffer
            uint256 balanceBefore = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferBefore = IERC20(MC.WETH).balanceOf(vault.buffer());

            bufferShares = ProcessorUtils.allocateToBuffer(vault, bufferAmount, PROCESSOR);
            // vault.processAccounting(); // already called in ProcessorUtils.allocateToBuffer

            uint256 balanceAfter = IERC20(MC.WETH).balanceOf(address(vault));
            uint256 bufferAfter = IERC20(MC.WETH).balanceOf(vault.buffer());
            assertEq(balanceBefore - balanceAfter, bufferAmount, "WETH balance should decrease by buffer amount");
            assertEq(bufferAfter - bufferBefore, bufferAmount, "Buffer balance should increase by buffer amount");
        }

        assertGt(bufferShares, 0, "Buffer shares should be greater than 0");

        uint256 bufferRate = IProvider(vault.provider()).getRate(vault.buffer());
        uint256 bufferAssets = Math.mulDiv(bufferShares, bufferRate, 1e18, Math.Rounding.Floor);

        assertApproxEqRel(bufferAssets, bufferAmount, 1e13, "Buffer assets should equal buffer amount");

        totalSupplyInvariant(initialSupply);
        totalAssetsInvariant(initialAssets - bufferAmount + bufferAssets);
    }

    function testDonationToBuffer_withoutBufferAllocation() public {
        uint256 assets = 1 ether;
        uint256 bufferAmount = 0.5 ether;

        HooksUtils.setMaxTotalAssetsIncreaseRatio(vault, 1 ether);
        HooksUtils.setMaxTotalAssetsDecreaseRatio(vault, 1 ether);
        HooksUtils.setMaxTotalSupplyIncreaseRatio(vault, 1 ether);

        setMockBuffer();

        // Initial state
        uint256 initialSupply = vault.totalSupply();
        uint256 initialAssets = vault.totalAssets();

        // Make initial deposit
        deal(address(this), assets);
        (bool success,) = MC.WETH.call{value: assets}("");
        assertTrue(success, "Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, address(this));

        // Process accounting
        vault.processAccounting();

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);

        // // Donate directly to buffer
        deal(address(this), 1 ether);
        (success,) = MC.WETH.call{value: 1 ether}("");
        assertTrue(success, "Weth deposit failed");
        IERC20(MC.WETH).transfer(vault.buffer(), 1 ether);

        // // Allocate to buffer
        ProcessorUtils.allocateToBuffer(vault, bufferAmount, PROCESSOR);

        // vault.processAccounting(); // already called in ProcessorUtils.allocateToBuffer

        totalSupplyInvariant(initialSupply + shares);
        // assets go down because of buffer donation  - THIS MUST BE AVOIDED
        totalAssetsInvariant(initialAssets + (assets - bufferAmount));
    }

    function setMockBuffer() internal {
        // Deploy mock buffer
        MockERC4626 mockBuffer = new MockERC4626(ERC20(MC.WETH), "Mock Buffer", "BUFF");

        // Deploy mock provider
        MockProvider mockProvider = new MockProvider();

        // Configure mock provider to use ERC4626 rate for buffer
        mockProvider.addERC4626(address(mockBuffer));

        vm.startPrank(MC.TIMELOCK);

        // Set mock buffer address
        vault.setBuffer(address(mockBuffer));

        // Set mock provider address
        vault.setProvider(address(mockProvider));

        // Add mock buffer as an asset
        vault.addAsset(address(mockBuffer), false);

        vm.stopPrank();

        // Grant PROCESSOR_MANAGER_ROLE to this contract
        vm.startPrank(ADMIN);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vm.stopPrank();

        _setupRules(address(mockBuffer));
    }

    function _setupRules(address mockBuffer) internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](2);
        rules[0] = BaseRules.getApprovalRule(MC.WETH, address(mockBuffer));
        rules[1] = BaseRules.getDepositRule(address(mockBuffer), address(vault));
        SafeRules.setProcessorRules(vault, rules, true);
    }
}

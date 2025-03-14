// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {TransparentUpgradeableProxy, IERC20, Math} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MockERC20CustomDecimals} from "test/unit/mocks/MockERC20CustomDecimals.sol";
import {MainnetActors} from "script/Actors.sol";
import {PublicViewsStrategy} from "test/unit/helpers/PublicViewsStrategy.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IProvider} from "src/interface/IProvider.sol";

contract StrategyRatesUnitTest is Test, MainnetActors {
    PublicViewsStrategy public vault;
    IProvider public provider;

    IERC20 public asset1;
    IERC20 public asset2;
    IERC20 public asset3;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public chad = address(0x3);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        string memory name = "YieldNest Strategy";
        string memory symbol = "ynStrat";

        PublicViewsStrategy vaultImplementation = new PublicViewsStrategy();

        // Deploy the proxy
        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, "");

        vault = PublicViewsStrategy(payable(address(vaultProxy)));

        // Initialize the vault
        vault.initialize(ADMIN, name, symbol, 18, true, true);

        asset1 = IERC20(new MockERC20CustomDecimals("Asset 1", "A1", 18));
        asset2 = IERC20(new MockERC20CustomDecimals("Asset 2", "A2", 12));
        asset3 = IERC20(new MockERC20CustomDecimals("Asset 3", "A3", 6));

        MockProvider mockProvider = new MockProvider();

        mockProvider.setRate(address(asset1), 1e18);
        mockProvider.setRate(address(asset2), 1e18);
        mockProvider.setRate(address(asset3), 1e18);

        provider = IProvider(mockProvider);

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        vault.setProvider(address(provider));

        vault.addAsset(address(asset1), 18, true, true);
        vault.addAsset(address(asset2), 12, true, true);
        vault.addAsset(address(asset3), 6, true, true);

        vault.unpause();

        vm.stopPrank();
    }

    function test_Strategy_views() public view {
        assertEq(vault.name(), "YieldNest Strategy");
        assertEq(vault.symbol(), "ynStrat");
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.paused(), false);
        assertEq(vault.provider(), address(provider));

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 3);
    }

    function depositIntoVault(address assetAddress, address depositor, uint256 amount)
        internal
        returns (uint256 shares)
    {
        IERC20 asset = IERC20(assetAddress);

        uint256 beforeTotalAssets = vault.totalAssets();
        uint256 beforeTotalShares = vault.totalSupply();
        uint256 beforeVaultBalance = asset.balanceOf(address(vault));
        uint256 beforeDepositorBalance = asset.balanceOf(depositor);
        uint256 beforeDepositorShares = vault.balanceOf(depositor);
        uint256 beforeMaxWithdraw = vault.maxWithdrawAsset(assetAddress, depositor);
        assertEq(beforeMaxWithdraw, 0, "Depositor should have no max withdraw before deposit");

        uint256 previewShares = vault.previewDepositAsset(assetAddress, amount);

        vm.prank(depositor);
        asset.approve(address(vault), amount);

        // Test the deposit function
        vm.prank(depositor);
        shares = vault.depositAsset(assetAddress, amount, depositor);

        assertEq(previewShares, shares, "Preview shares should be equal to shares");

        assertEq(
            vault.totalAssets(),
            beforeTotalAssets + vault.convertToAssets(shares),
            "Total assets should increase by the amount deposited"
        );
        assertEq(
            vault.totalSupply(), beforeTotalShares + shares, "Total shares should increase by the amount deposited"
        );

        assertEq(
            asset.balanceOf(address(vault)), beforeVaultBalance + amount, "Vault should have the asset after deposit"
        );
        assertEq(asset.balanceOf(depositor), beforeDepositorBalance - amount, "From should not have the assets");
        assertEq(vault.balanceOf(depositor), beforeDepositorShares + shares, "From should have shares after deposit");
        assertApproxEqAbs(
            vault.maxWithdrawAsset(address(asset), depositor),
            beforeMaxWithdraw + amount,
            2,
            "Depositor should have max withdraw after deposit"
        );
    }

    function withdrawFromVault(address assetAddress, address withdrawer, uint256 withdrawAmount) internal virtual {
        IERC20 asset = IERC20(assetAddress);

        // Initial balances
        uint256 withdrawerAssetBefore = asset.balanceOf(withdrawer);
        uint256 withdrawerSharesBefore = vault.balanceOf(withdrawer);

        // Store initial state
        uint256 initialTotalAssets = vault.totalAssets();
        uint256 initialTotalSupply = vault.totalSupply();

        // Store initial vault Asset balance
        uint256 vaultAssetBefore = asset.balanceOf(address(vault));

        vm.startPrank(withdrawer);

        // Deposit Asset to get shares
        uint256 shares = vault.withdrawAsset(address(asset), withdrawAmount, withdrawer, withdrawer);

        vm.stopPrank();

        // Check balances after deposit
        assertEq(asset.balanceOf(withdrawer), withdrawerAssetBefore + withdrawAmount, "Asset balance incorrect");
        assertEq(vault.balanceOf(withdrawer), withdrawerSharesBefore - shares, "Should have burnt shares");

        // Check vault state after deposit
        assertEq(
            vault.totalAssets(), initialTotalAssets - withdrawAmount, "Total assets should decrease by withdraw amount"
        );
        assertEq(vault.totalSupply(), initialTotalSupply - shares, "Total supply should decrease by shares");

        // Check that vault Asset balance increased by deposit amount
        assertEq(
            asset.balanceOf(address(vault)),
            vaultAssetBefore - withdrawAmount,
            "Vault balance should decrease by withdraw amount"
        );
    }

    function test_Strategy_view_rates() public view {
        assertEq(vault.convertAssetToBase(address(asset1), 1e18), 1e18, "Asset 1 to base should be correct");
        assertEq(vault.convertAssetToBase(address(asset2), 1e12), 1e18, "Asset 2 to base should be correct");
        assertEq(vault.convertAssetToBase(address(asset3), 1e6), 1e18, "Asset 3 to base should be correct");

        assertEq(vault.convertBaseToAsset(address(asset1), 1e18), 1e18, "Asset 1 from base should be correct");
        assertEq(vault.convertBaseToAsset(address(asset2), 1e18), 1e12, "Asset 2 from base should be correct");
        assertEq(vault.convertBaseToAsset(address(asset3), 1e18), 1e6, "Asset 3 from base should be correct");
    }

    function test_Strategy_deposit_asset1(uint256 amount) public {
        vm.assume(amount >= 0.001 ether && amount <= 1000 ether);

        deal(address(asset1), bob, amount);

        depositIntoVault(address(asset1), bob, amount);
    }

    function test_Strategy_deposit_asset2(uint256 amount) public {
        vm.assume(amount >= 0.002 ether && amount <= 2000 ether);

        deal(address(asset2), bob, amount);

        depositIntoVault(address(asset2), bob, amount);
    }

    function test_Strategy_deposit_asset3(uint256 amount) public {
        vm.assume(amount >= 0.003 ether && amount <= 3000 ether);

        deal(address(asset3), bob, amount);

        depositIntoVault(address(asset3), bob, amount);
    }

    function test_Strategy_multiple_deposits() public {
        deal(address(asset1), bob, 1e18);
        deal(address(asset2), bob, 1e12);
        deal(address(asset3), bob, 1e6);

        depositIntoVault(address(asset1), bob, 1e18);
        depositIntoVault(address(asset2), bob, 1e12);
        depositIntoVault(address(asset3), bob, 1e6);

        assertEq(vault.totalAssets(), 3e18, "Total assets should be 3e18");
    }

    function test_Strategy_withdrawal_asset1(uint256 amount) public {
        vm.assume(amount >= 0.001 ether && amount <= 1000 ether);

        deal(address(asset1), bob, amount);

        depositIntoVault(address(asset1), bob, amount);

        withdrawFromVault(address(asset1), bob, amount);
    }

    function test_Strategy_withdrawal_withRewards(uint256 amount, uint256 rewards) public {
        // amount is in 18 decimals, enzoBTC is in 8 decimals so starting at 1e11
        vm.assume(amount >= 1e14 && amount <= 1000 ether);
        vm.assume(rewards >= 0 && rewards <= amount);

        {
            deal(address(asset1), alice, amount);
            depositIntoVault(address(asset1), alice, amount);

            deal(address(asset2), alice, amount / 1e6);
            depositIntoVault(address(asset2), alice, amount / 1e6);

            deal(address(asset3), alice, amount / 1e12);
            depositIntoVault(address(asset3), alice, amount / 1e12);

            // Process accounting to ensure deposit is reflected
            vault.processAccounting();

            // Get additional enzoBTC for rewards
            deal(address(asset3), bob, rewards);

            // Transfer rewards to the vault
            vm.prank(bob);
            asset3.transfer(address(vault), rewards);

            // Process accounting to reflect rewards
            vault.processAccounting();
        }

        // Perform max withdraw
        uint256 maxWithdraw = vault.maxWithdrawAsset(address(asset3), bob);

        // Store the conversion rates before withdrawal
        (uint256 assetsBeforeWithdrawCeil,) = vault.convertToAssetsForAsset(address(asset1), 1e18, Math.Rounding.Ceil);
        (uint256 sharesBeforeWithdrawCeil,) = vault.convertToSharesForAsset(address(asset1), 1e18, Math.Rounding.Ceil);

        (uint256 assetsBeforeWithdrawFloor,) = vault.convertToAssetsForAsset(address(asset1), 1e18, Math.Rounding.Floor);
        (uint256 sharesBeforeWithdrawFloor,) = vault.convertToSharesForAsset(address(asset1), 1e18, Math.Rounding.Floor);

        vm.prank(bob);
        vault.withdrawAsset(address(asset3), maxWithdraw, bob, bob);

        (uint256 assetsAfterWithdrawFloor,) = vault.convertToAssetsForAsset(address(asset1), 1e18, Math.Rounding.Floor);
        (uint256 sharesAfterWithdrawFloor,) = vault.convertToSharesForAsset(address(asset1), 1e18, Math.Rounding.Floor);

        (uint256 assetsAfterWithdrawCeil,) = vault.convertToAssetsForAsset(address(asset1), 1e18, Math.Rounding.Ceil);
        (uint256 sharesAfterWithdrawCeil,) = vault.convertToSharesForAsset(address(asset1), 1e18, Math.Rounding.Ceil);

        // Assert rate stayed the same after withdrawal
        assertApproxEqAbs(
            assetsAfterWithdrawFloor,
            assetsBeforeWithdrawFloor,
            1e6,
            "Floor Rate should remain unchanged after withdrawal"
        );
        assertApproxEqAbs(
            sharesAfterWithdrawFloor,
            sharesBeforeWithdrawFloor,
            1e6,
            "Floor Shares conversion rate should remain unchanged after withdrawal"
        );

        assertApproxEqAbs(
            assetsAfterWithdrawCeil, assetsBeforeWithdrawCeil, 1e6, "Ceil Rate should remain unchanged after withdrawal"
        );

        assertApproxEqAbs(
            sharesAfterWithdrawCeil,
            sharesBeforeWithdrawCeil,
            1e6,
            "Ceil Shares conversion rate should remain unchanged after withdrawal"
        );

        // Assert rate increased for Floor after withdrawal (assets per share decreased)
        assertGe(
            assetsAfterWithdrawFloor,
            assetsBeforeWithdrawFloor,
            "Floor Rate should increase after withdrawal (fewer assets per share)"
        );
        assertLe(
            sharesAfterWithdrawFloor,
            sharesBeforeWithdrawFloor,
            "Floor Shares conversion rate should decrease after withdrawal (more shares per asset)"
        );

        // Assert rate decreased for Ceil after withdrawal (assets per share decreased)
        assertLe(
            assetsAfterWithdrawCeil,
            assetsBeforeWithdrawCeil,
            "Ceil Rate should decrease after withdrawal (fewer assets per share)"
        );
        assertGe(
            sharesAfterWithdrawCeil,
            sharesBeforeWithdrawCeil,
            "Ceil Shares conversion rate should increase after withdrawal (more shares per asset)"
        );
    }
}

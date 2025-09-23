// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ViewUtils} from "test/utils/ViewUtils.sol";
import {MockERC4626, ERC20} from "test/mainnet/mocks/MockERC4626.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";

contract VaultMainnetInvariantsTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    address public user = makeAddr("user");
    MockERC4626 public mockAsset;

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        // Create and initialize mock ERC4626 asset
        mockAsset = new MockERC4626(ERC20(MC.WETH), "MOCK ERC4626 WETH", "MOCKETH");

        assertEq(vault.baseWithdrawalFee(), 250000, "base withdrawal fee should be correct");

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_processAccounting_withDonation(uint256 depositAmount, uint256 donationPercent) public {
        // Bound inputs to reasonable ranges
        depositAmount = bound(depositAmount, 1 ether, 1000000 ether);
        donationPercent = bound(donationPercent, 1, 50); // 1% to 50% donation

        uint256 donationAmount = depositAmount * donationPercent / 100;

        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        // Now donate the additional amount
        deal(MC.WETH, address(this), donationAmount);
        IERC20(MC.WETH).transfer(address(vault), donationAmount);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        uint256 performanceFeeSharesBefore =
            address(vault.hooks()) != address(0) ? ViewUtils.getPerformanceFeeReceiverBalance(vault) : 0;

        vault.processAccounting();

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // Verify that total assets increased by the donation amount
        assertEq(
            totalAssetsAfter,
            totalAssetsBefore + donationAmount,
            "Total assets should increase by exactly the donation amount"
        );

        if (address(vault.hooks()) == address(0)) {
            // If no hooks are set, total supply should remain unchanged
            assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged when no hooks are set");
        } else {
            // Calculate expected delta based on donation amount for fee calculations
            uint256 expectedDeltaShares = vault.convertToShares(
                donationAmount.mulDiv(ViewUtils.getPerformanceFee(vault), 1 ether, Math.Rounding.Floor)
            );

            uint256 performanceFeeSharesAfter = ViewUtils.getPerformanceFeeReceiverBalance(vault);

            uint256 performanceFeeSharesDelta = performanceFeeSharesAfter - performanceFeeSharesBefore;
            assertApproxEqAbs(
                performanceFeeSharesDelta,
                expectedDeltaShares,
                1,
                "Performance fee shares should increase by the expected delta"
            );

            // Verify that total supply increased by the expected fee shares
            assertApproxEqAbs(
                totalSupplyAfter,
                totalSupplyBefore + performanceFeeSharesDelta,
                1,
                "Total supply should increase by performance fee shares"
            );
        }
    }

    function test_processAccounting_with_zero_gains() public {
        deal(MC.WETH, address(this), 100000 ether);
        IERC20(MC.WETH).approve(address(vault), 100000 ether);
        vault.depositAsset(MC.WETH, 100000 ether, address(this));
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        vault.processAccounting();

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // With zero gains, total assets should remain unchanged
        assertEq(totalAssetsAfter, totalAssetsBefore, "Total assets should remain unchanged with zero gains");

        // With zero gains, total supply should remain unchanged
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged with zero gains");
    }

    function test_processAccounting_with_a_loss() public {
        // Deploy MockProvider and add mockAsset to it
        MockProvider mockProvider = new MockProvider();
        mockProvider.addERC4626(address(mockAsset));

        // Set the mock provider
        vm.prank(MC.TIMELOCK);
        vault.setProvider(address(mockProvider));

        // Add the new asset
        vm.prank(MC.TIMELOCK);
        vault.addAsset(address(mockAsset), true);

        // Mint mockAsset tokens
        address minter = makeAddr("minter");
        deal(MC.WETH, minter, 100000 ether);
        vm.prank(minter);
        IERC20(MC.WETH).approve(address(mockAsset), 100000 ether);
        vm.prank(minter);
        mockAsset.deposit(100000 ether, minter);

        // Deposit mockAsset tokens to vault
        uint256 mockTokenBalance = mockAsset.balanceOf(minter);
        vm.prank(minter);
        mockAsset.approve(address(vault), mockTokenBalance);
        vm.prank(minter);
        vault.depositAsset(address(mockAsset), mockTokenBalance, minter);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();

        // Slash the mockAsset to create a loss
        mockAsset.slash(0.01 ether); // Slash 1% of underlying assets

        vault.processAccounting();

        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();

        // With a loss, total assets should decrease
        assertLt(totalAssetsAfter, totalAssetsBefore, "Total assets should decrease with a loss");

        // With a loss, total supply should remain unchanged (no fee minting)
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply should remain unchanged with a loss");
    }
}

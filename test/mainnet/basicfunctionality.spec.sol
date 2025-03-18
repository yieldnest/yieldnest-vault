// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController, IERC20, Math, ERC20} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IVault} from "src/interface/IVault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {BaseVault} from "src/BaseVault.sol";
import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {RulesVerification} from "script/verification/RulesVerification.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";

contract VaultBasicFunctionalityTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    BufferStrategy public bufferStrategy;
    Provider public provider;

    string public constant VAULT_VERSION = "0.1.0";

    function setUp() public {
        (vault, bufferStrategy, provider) = BaseTest.deploy();
        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_deposit_USDC(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, 100_000 * 1e6);

        deal(MC.USDC, address(this), depositAmount);
        uint256 totalAssetBefore = vault.totalAssets();

        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.depositAsset(MC.USDC, depositAmount, address(this));
        vault.processAccounting();

        uint256 totalAssets = vault.totalAssets();
        uint256 ynUSDCRate = IProvider(vault.provider()).getRate(MC.USDC);

        assertEq(
            totalAssets,
            totalAssetBefore + (depositAmount * ynUSDCRate / 1e6),
            "Total assets should match deposit amount"
        );
    }

    function test_can_not_deposit_other_assets(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1, 100_000 * 1e6);
        address[] memory assets = vault.getAssets();
        for(uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            
            if(asset == MC.USDC) {
                continue;
            }

            deal(asset, address(this), depositAmount);
            uint256 totalAssetBefore = vault.totalAssets();

            IERC20(asset).forceApprove(address(vault), depositAmount);
            vm.expectRevert();
            vault.depositAsset(asset, depositAmount, address(this));
            vault.processAccounting();

            assertEq(vault.totalAssets(), totalAssetBefore, "Total assets should not change");
        }
    }

    function test_donate_assets(uint256 donationAmount) public {

        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            donationAmount = bound(donationAmount, 100, 100_000 * 10 ** ERC20(assets[i]).decimals());
            _test_donate_single_asset(assets[i], donationAmount);
        }
    }

    function _test_donate_single_asset(address asset, uint256 donationAmount) internal {
        address alice = address(0xa11ce);

        uint256 totalAssetBefore = vault.totalAssets();

        assertEq(IERC20(asset).balanceOf(alice), 0, "Balance should be 0 before donation");

        deal(asset, alice, donationAmount);

        vm.startPrank(alice);
        IERC20(asset).safeTransfer(address(vault), donationAmount);
        vm.stopPrank();

        vault.processAccounting();

        uint256 rate = IProvider(vault.provider()).getRate(asset);
        uint256 baseAmount = Math.mulDiv(donationAmount, rate, 10 ** ERC20(asset).decimals(), Math.Rounding.Floor);

        assertEq(vault.totalAssets(), totalAssetBefore + baseAmount, "Total assets should be correct");
    }

    function test_deposit_any_asset(uint256 depositAmount, uint256 assetIndex) public {

        address[] memory assets = vault.getAssets();
        assetIndex = bound(assetIndex, 0, assets.length - 1);
        address asset = assets[assetIndex];

        depositAmount = bound(depositAmount, 1, 1000_000 * 10 ** ERC20(asset).decimals());

        address alice = address(0xa11ce);
        deal(asset, alice, depositAmount);

        // Skip if asset is already active
        if (!vault.getAsset(asset).active) {
            vm.startPrank(address(ADMIN));
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(assetIndex, fields);
            vm.stopPrank();
        }

        vault.processAccounting();

        uint256 totalAssetBefore = vault.totalAssets();
        uint256 vaultRateBefore = vault.convertToAssets(1e18);

        vm.startPrank(alice);
        IERC20(asset).forceApprove(address(vault), depositAmount);
        vault.depositAsset(asset, depositAmount, address(this));
        vm.stopPrank();

        vault.processAccounting();

        uint256 totalAssets = vault.totalAssets();
        uint256 assetRate = IProvider(vault.provider()).getRate(asset);
        uint256 vaultRateAfterDeposit = vault.convertToAssets(1e18);

        assertApproxEqRel(vaultRateBefore, vaultRateAfterDeposit, 1e10, "Vault rate should not change after deposit");
        uint256 baseAmount = Math.mulDiv(depositAmount, assetRate, 10 ** ERC20(asset).decimals(), Math.Rounding.Floor);

        assertApproxEqAbs(
            totalAssets,
            totalAssetBefore + baseAmount,
            3,
            "Total assets should match deposit amount"
        );


        uint256 vaultRateAfterProcessing = vault.convertToAssets(1e18);
        assertApproxEqRel(
            vaultRateAfterDeposit, vaultRateAfterProcessing, 1e10, "Vault rate should not change after processing"
        );

        // Verify total assets remains the same after processing accounting
        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetBefore + baseAmount,
            3,
            "Total assets should match deposit amount"
        );
    }

    function testDonateOETHAndWithdraw(uint256 donationAmount) public {
        // uint256 donationAmount = 100e18;
        vm.assume(donationAmount > 1e9);
        vm.assume(donationAmount < 100_000 ether);
        uint256 donateAmount;
        address asset = MC.OETH;

        uint256 initialVaultOETH = IERC20(asset).balanceOf(address(vault));
        uint256 initialWithdrawerOETH = IERC20(asset).balanceOf(address(withdrawer));

        address alice = makeAddr("alice");
        {
            dealAsset(asset, alice, donationAmount);

            donateAmount = IERC20(asset).balanceOf(alice);

            vm.startPrank(alice);
            IERC20(asset).transfer(address(vault), donateAmount);
            vm.stopPrank();
        }

        vault.processAccounting();

        uint256 tvlBeforeWithdraw = vault.totalAssets();

        {
            // Approve and deposit OETH to withdrawer
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = asset;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(withdrawer), donateAmount));

            targets[1] = address(withdrawer);
            values[1] = 0;
            data[1] = abi.encodeCall(BaseVault.depositAsset, (MC.OETH, donateAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, data);
            vm.stopPrank();

            assertEq(
                IERC20(asset).balanceOf(address(vault)),
                initialVaultOETH,
                "Vault OETH balance should match initial balance"
            );

            assertEq(
                IERC20(asset).balanceOf(address(withdrawer)),
                initialWithdrawerOETH + donateAmount,
                "Withdrawer OETH balance should match initial plus donated amount"
            );
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        assertEq(vault.totalAssets(), tvlBeforeWithdraw, "Total assets should match after deposit to withdrawer");

        uint256 tokenId;
        {
            vm.startPrank(PROCESSOR);
            tokenId = withdrawer.requestWithdrawalOETH(donateAmount);
            vm.stopPrank();

            assertEq(
                IERC20(asset).balanceOf(address(withdrawer)),
                initialWithdrawerOETH,
                "Withdrawer OETH balance should be back to initial amount"
            );

            assertEq(
                withdrawer.asyncWithdrawalBalance(MC.WOETH),
                donateAmount,
                "Async withdrawal balance for WOETH should match donated amount"
            );

            // OETH withdrawn balance is 0 as the withdrawn balance is associated with WOETH
            assertEq(
                withdrawer.asyncWithdrawalBalance(MC.OETH), 0, "Async withdrawal balance for OETH should always be zero"
            );
        }

        assertNotEq(tokenId, 0, "Token ID should not be zero");

        withdrawer.processAccounting();
        // Process accounting to reflect changes
        vault.processAccounting();

        // TVL should remain unchanged since OETH was donated and withdrawn
        assertApproxEqAbs(
            vault.totalAssets(), tvlBeforeWithdraw, 3, "Total assets should remain unchanged after OETH withdrawal"
        );

        uint256 withdrawerTotalBefore = withdrawer.totalAssets();
        uint256 withdrawerSharesBalance = withdrawer.balanceOf(address(vault));

        address[] memory assets = vault.getAssets();
        uint256[] memory initialBalances = new uint256[](assets.length);
        uint256[] memory initialRates = new uint256[](assets.length);
        uint256 initialTotalAssets = address(vault).balance;
        for (uint256 i = 0; i < assets.length; i++) {
            initialBalances[i] = IERC20(assets[i]).balanceOf(address(vault));
            initialRates[i] = IProvider(vault.provider()).getRate(assets[i]);
            initialTotalAssets += initialBalances[i] * initialRates[i] / 1e18;
        }

        assertApproxEqAbs(tvlBeforeWithdraw, initialTotalAssets, 3, "Total assets should match before OETH withdrawal");

        _claimWithdrawalWOETH(tokenId, donateAmount);

        // Process accounting and verify total assets remain unchanged
        withdrawer.processAccounting();
        vault.processAccounting();

        assertEq(
            IERC20(asset).balanceOf(address(vault)), initialVaultOETH, "Vault OETH balance should match initial balance"
        );

        assertEq(
            IERC20(asset).balanceOf(address(withdrawer)),
            initialWithdrawerOETH,
            "Withdrawer OETH balance should be back to initial amount"
        );

        assertEq(withdrawer.asyncWithdrawalBalance(MC.WOETH), 0, "Async withdrawal balance for WOETH should be zero");

        assertEq(
            withdrawer.balanceOf(address(vault)),
            withdrawerSharesBalance,
            "Withdrawer shares balance should remain unchanged"
        );

        assertApproxEqAbs(
            withdrawer.totalAssets(), withdrawerTotalBefore, 3, "Withdrawer total assets should remain unchanged"
        );

        uint256[] memory finalBalances = new uint256[](assets.length);
        uint256[] memory finalRates = new uint256[](assets.length);
        uint256 finalTotalAssetsCalculated = address(vault).balance;
        for (uint256 i = 0; i < assets.length; i++) {
            finalBalances[i] = IERC20(assets[i]).balanceOf(address(vault));
            assertEq(finalBalances[i], initialBalances[i], "Balance should match");
            finalRates[i] = IProvider(vault.provider()).getRate(assets[i]);
            finalTotalAssetsCalculated += finalBalances[i] * finalRates[i] / 1e18;

            // TODO: understand why the rate is changing this much
            // rate is changing for underlying assets
            assertApproxEqRel(finalRates[i], initialRates[i], 2e14, "Rate should match");
        }

        uint256 finalTvl = vault.totalAssets();
        assertEq(finalTvl, finalTotalAssetsCalculated, "Total assets should match after OETH withdrawal");

        // The rates of underlying assets changes, consequently the total assets changes slightly
        assertApproxEqRel(
            finalTvl, tvlBeforeWithdraw, 1e13, "Total assets should remain unchanged after processing accounting"
        );
    }

    function _claimWithdrawalWOETH(uint256 tokenId, uint256 donateAmount) internal {
        IERC20 weth = IERC20(MC.WETH);
        IOETHVault oethVault = IOETHVault(MC.OETH_VAULT);

        uint256 withdrawerWethBefore = weth.balanceOf(address(withdrawer));

        vm.startPrank(oethVault.governor());
        oethVault.setMaxSupplyDiff(0);
        vm.stopPrank();

        {
            IOETHVault.WithdrawalQueueMetadata memory queue = oethVault.withdrawalQueueMetadata();
            uint256 outstandingWithdrawals = queue.queued - queue.claimed;
            address alice = makeAddr("alice");
            deal(MC.WETH, alice, outstandingWithdrawals + donateAmount);

            vm.startPrank(alice);
            weth.approve(address(oethVault), outstandingWithdrawals + donateAmount);
            oethVault.mint(address(weth), outstandingWithdrawals + donateAmount, 1);
            vm.stopPrank();

            assertGt(weth.balanceOf(MC.OETH_VAULT), donateAmount + outstandingWithdrawals, "WETH balance should match");

            // solhint-disable-next-line not-rely-on-time
            uint256 timestamp = block.timestamp;
            vm.warp(timestamp + oethVault.withdrawalClaimDelay() + 10 minutes);

            uint256[] memory tokenIds = new uint256[](1);
            tokenIds[0] = tokenId;

            vm.prank(PROCESSOR);
            withdrawer.claimWithdrawalsWOETH(tokenIds);
        }

        assertEq(
            IERC20(MC.WETH).balanceOf(address(withdrawer)),
            donateAmount + withdrawerWethBefore,
            "WETH balance of withdrawer should match donated amount"
        );
    }

    function test_depositWETH_allocateToYnETH(uint256 depositAmount) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 vaultBalanceBefore = IERC20(MC.WETH).balanceOf(address(vault));
        uint256 ynEthBalanceBefore = IERC20(MC.YNETH).balanceOf(address(vault));

        // Deposit WETH to vault
        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        // Process accounting
        vault.processAccounting();
        withdrawer.processAccounting();

        // Verify WETH was transferred to withdrawer
        assertEq(
            IERC20(MC.WETH).balanceOf(address(vault)),
            vaultBalanceBefore + depositAmount,
            "WETH should be transferred to vault"
        );

        uint256 depositedAmount;
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = MC.WETH;
            values[0] = 0;
            data[0] = abi.encodeCall(IWETH.withdraw, (depositAmount));

            targets[1] = address(MC.YNETH);
            values[1] = depositAmount;
            data[1] = abi.encodeCall(IynETH.depositETH, (address(vault)));

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();

            depositedAmount = abi.decode(returnData[1], (uint256));
        }

        // Process accounting
        vault.processAccounting();
        withdrawer.processAccounting();

        uint256 rate = IProvider(vault.provider()).getRate(MC.YNETH);
        uint256 baseAmount = Math.mulDiv(depositedAmount, rate, 10 ** 18, Math.Rounding.Floor);

        // Verify total assets increased by correct amount
        assertApproxEqAbs(
            vault.totalAssets(), totalAssetsBefore + baseAmount, 3, "Total assets should match deposit amount"
        );

        // Verify ynETH balance matches expected amount based on rate
        assertApproxEqAbs(
            IERC20(MC.YNETH).balanceOf(address(vault)),
            ynEthBalanceBefore + depositedAmount,
            3,
            "ynETH balance should match expected amount"
        );
    }

    function test_depositAndWithdrawFromBuffer() public {
        uint256 depositAmount =  100_000e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        // Get initial balances
        uint256 aliceUSDCBalanceBefore = IERC20(MC.USDC).balanceOf(alice);
        uint256 vaultTotalAssetsBefore = vault.totalAssets();

        // Approve and deposit USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit
        assertEq(
            IERC20(MC.USDC).balanceOf(alice),
            aliceUSDCBalanceBefore - depositAmount,
            "User USDC balance should decrease by deposit amount"
        );
        uint256 rate = IProvider(vault.provider()).getRate(MC.USDC);
        uint256 baseAmount = Math.mulDiv(depositAmount, rate, 10 ** ERC20(MC.USDC).decimals(), Math.Rounding.Floor);
        assertEq(vault.totalAssets(), vaultTotalAssetsBefore + baseAmount, "Vault total assets should increase");
        assertEq(vault.balanceOf(alice), vault.totalSupply(), "Vault balance of alice should increase");

        uint256 bufferStrategyBalanceBefore = bufferStrategy.balanceOf(address(vault));
        uint256 bufferStrategyTotalSupplyBefore = bufferStrategy.totalSupply();
        // Allocate to buffer (MorphoGauntletUSDC vault)
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = MC.USDC;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(bufferStrategy), depositAmount));

            targets[1] = address(bufferStrategy);
            values[1] = 0;
            data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, data);
            vm.stopPrank();
        }

        // Process accounting
        vault.processAccounting();

        // User withdraws max amount
        vm.startPrank(alice);
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vault.withdraw(maxWithdraw, alice, alice);
        vm.stopPrank();
        // Calculate withdrawal fee
        uint256 fee = depositAmount * vault.baseWithdrawalFee() / 1e8;
        uint256 amountAfterFee = depositAmount - fee;

        // Verify withdrawal
        assertApproxEqAbs(
            IERC20(MC.WETH).balanceOf(alice),
            aliceWethBalanceBefore - depositAmount + amountAfterFee,
            // TODO: fix this down to at least 1e8 margin of error
            1e15, // withdrawal fee precision error is at 0.01% of amount
            "User should receive original WETH amount back minus fee"
        );
        assertApproxEqAbs(
            vault.totalAssets(),
            vaultTotalAssetsBefore + fee,
            1e15, // withdrawal fee precision error is at 0.01% of amount
            "Vault total assets should include withdrawal fee"
        );
    }

    function testDepositYnETHAndYnLSDeToConnector() public {
        uint256 depositAmount = 1000e18;
        uint256 vaultTotalAssetsBefore = vault.totalAssets();

        address alice = makeAddr("alice");
        {
            deal(MC.YNETH, alice, depositAmount);
            deal(MC.YNLSDE, alice, depositAmount);

            // Alice deposits equal amounts of ynETH and ynLSDe
            vm.startPrank(alice);
            IERC20(MC.YNETH).approve(address(vault), depositAmount);
            IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
            vault.depositAsset(MC.YNETH, depositAmount, alice);
            vault.depositAsset(MC.YNLSDE, depositAmount, alice);
            vm.stopPrank();

            // Process accounting
            vault.processAccounting();
        }

        {
            uint256 expectedUsdcCoreVaultShares = IERC4626(MC.MORPHO_GAUNTLET_USDC_VAULT).previewDeposit(depositAmount);
            assertEq(IERC20(MC.USDC).balanceOf(address(bufferStrategy)), 0, "Buffer strategy should deposit USDC to usdc core vault");
            assertEq(IERC4626(MC.MORPHO_GAUNTLET_USDC_VAULT).balanceOf(address(bufferStrategy)), expectedUsdcCoreVaultShares, "Buffer strategy should receive shares from usdc core vault");
            assertEq(bufferStrategy.balanceOf(address(vault)), bufferStrategy.totalSupply() - bufferStrategyTotalSupplyBefore, "Buffer strategy balance of vault should increase");
        }
        {
            uint256 vaultBalanceBeforeWithdraw = vault.balanceOf(alice);
            // User withdraws max amount
            vm.startPrank(alice);
            uint256 maxWithdraw = vault.maxWithdraw(alice);
            uint256 sharesBurned = vault.previewWithdraw(maxWithdraw);
            vault.withdraw(maxWithdraw, alice, alice);
            vm.stopPrank();

            // Calculate withdrawal fee
            uint256 fee = depositAmount * vault.baseWithdrawalFee() / 1e8;
            uint256 amountAfterFee = depositAmount - fee;
            // Verify withdrawal
            assertApproxEqAbs(
                IERC20(MC.USDC).balanceOf(alice),
                aliceUSDCBalanceBefore - depositAmount + amountAfterFee,
                10, // withdrawal fee precision error is at 0.001% of amount
                "User should receive original USDC amount back minus fee"
            );
            assertEq(vault.balanceOf(alice), vaultBalanceBeforeWithdraw - sharesBurned, "Vault balance of alice should decrease by shares burned");
            assertApproxEqAbs(
                vault.totalAssets(),
                vaultTotalAssetsBefore + fee,
                1e12, // withdrawal fee precision error is at 0.001% of amount
                "Vault total assets should include withdrawal fee"
            );
        }
    }
}
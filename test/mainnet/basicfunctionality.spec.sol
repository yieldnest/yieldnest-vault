// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController, IERC20, Math} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IVault} from "src/interface/IVault.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {RolesVerification} from "script/verification/RolesVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {IynETH} from "test/interface/external/yieldnest/IynETH.sol";
import {IWETH} from "test/interface/external/ethereum/IWETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";
import {BaseVault} from "src/BaseVault.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {WithdrawerProcessorUtils} from "test/utils/WithdrawerProcessorUtils.sol";
import {IwstETH} from "test/interface/external/lido/IwstETH.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {HooksUtils} from "test/utils/HooksUtils.sol";

contract VaultBasicFunctionalityTest is BaseIntegrationTest, TestHelper {
    Withdrawer public withdrawer;
    TimelockController public timelock;

    string public constant VAULT_VERSION = "0.2.0";

    function setUp() public override {
        super.setUp();
        withdrawer = VaultVerification.getWithdrawer(vault);

        timelock = TimelockController(payable(MC.TIMELOCK));

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_configure() public view {
        // verify the configuration was successful
        IActors actors = IActors(payable(address(this)));

        VaultVerification.verifyProvider(Provider(IVault(address(vault)).provider()), withdrawer);

        VaultVerification.verifyVaultConfiguration(vault, withdrawer);

        // verify actors & timelock roles on vault
        RolesVerification.verifyDefaultRoles(vault, timelock, actors);
        RolesVerification.verifyRole(
            vault, actors.FEE_MANAGER(), vault.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        // verify proxy roles on vault
        RolesVerification.verifyProxyRoles(address(vault), MC.PROXY_ADMIN, address(timelock));

        // verify withdrawer config
        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);

        // verify actors & timelock roles on withdrawer
        RolesVerification.verifyDefaultRoles(withdrawer, timelock, actors);
        RolesVerification.verifyRole(
            withdrawer, address(vault), withdrawer.ALLOCATOR_ROLE(), true, "YnETHx has ALLOCATOR_ROLE"
        );

        address withdrawerProxyAdmin = ProxyUtils.getProxyAdmin(address(withdrawer));

        // verify proxy roles on withdrawer
        RolesVerification.verifyProxyRoles(address(withdrawer), withdrawerProxyAdmin, address(timelock));

        // verify timelock roles
        uint256 minDelay = 1 days;
        RolesVerification.verifyTimelockRoles(timelock, actors, minDelay);
    }

    function test_deposit_ynETH(uint256 depositAmount) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        {
            vm.startPrank(ADMIN);
            vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
            vm.stopPrank();

            uint256 index = vault.getAsset(MC.YNETH).index;
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(index, fields);
        }

        deal(MC.YNETH, address(this), depositAmount);
        uint256 totalAssetBefore = vault.totalAssets();

        IERC20(MC.YNETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNETH, depositAmount, address(this));
        vault.processAccounting();

        uint256 totalAssets = vault.totalAssets();
        uint256 ynEthRate = IProvider(vault.provider()).getRate(MC.YNETH);

        assertApproxEqAbs(
            totalAssets,
            totalAssetBefore + (depositAmount * ynEthRate / 1e18),
            3,
            "Total assets should match deposit amount"
        );
    }

    function test_deposit_ynLSDe(uint256 depositAmount) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        {
            vm.startPrank(ADMIN);
            vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
            vm.stopPrank();

            uint256 index = vault.getAsset(MC.YNLSDE).index;
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(index, fields);
        }

        uint256 totalAssetBefore = vault.totalAssets();

        // Deposit YNLSDE
        deal(MC.YNLSDE, address(this), depositAmount);
        IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNLSDE, depositAmount, address(this));

        vault.processAccounting();

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();

        uint256 ynLSDeRate = IProvider(vault.provider()).getRate(MC.YNLSDE);
        assertApproxEqAbs(
            totalAssets,
            totalAssetBefore + (depositAmount * ynLSDeRate / 1e18),
            3,
            "Total assets should match deposit amount"
        );
    }

    function test_deposit_wETH(uint256 depositAmount) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        uint256 totalAssetBefore = vault.totalAssets();

        // Deposit YN
        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        vault.processAccounting();

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();

        uint256 wethRate = IProvider(vault.provider()).getRate(MC.WETH);
        assertApproxEqAbs(
            totalAssets,
            totalAssetBefore + (depositAmount * wethRate / 1e18),
            3,
            "Total assets should match deposit amount"
        );
    }

    function test_donate_assets(uint256 donationAmount) public {
        vm.assume(donationAmount > 1e8);
        vm.assume(donationAmount < 1_000 ether);

        HooksUtils.setMaxTotalAssetsIncreaseRatio(vault, 1e19); // 1000% to give enough leeway
        HooksUtils.setMaxTotalSupplyIncreaseRatio(vault, 1e19); // 1000% to give enough leeway

        address[] memory assets = vault.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            _test_donate_single_asset(assets[i], donationAmount);
        }
    }

    function _test_donate_single_asset(address asset, uint256 donationAmount) internal {
        address alice = address(0xa11ce);

        uint256 totalAssetBefore = vault.totalAssets();

        assertEq(IERC20(asset).balanceOf(alice), 0, "Balance should be 0 before donation");

        dealAsset(asset, alice, donationAmount);

        //  note: donatedAmount is the actual amount donated to the vault
        uint256 donatedAmount = IERC20(asset).balanceOf(alice);

        vm.startPrank(alice);
        IERC20(asset).transfer(address(vault), donatedAmount);
        vm.stopPrank();

        vault.processAccounting();

        uint256 rate = IProvider(vault.provider()).getRate(asset);
        uint256 baseAmount = Math.mulDiv(donatedAmount, rate, 10 ** 18, Math.Rounding.Floor);

        assertApproxEqRel(vault.totalAssets(), totalAssetBefore + baseAmount, 2e12, "Total assets should be correct");
    }

    function test_deposit_any_asset(uint256 depositAmount, uint8 assetIndex) public {
        address[] memory assets = vault.getAssets();

        vm.assume(assetIndex < assets.length);
        {
            address[] memory skippedAssets = new address[](1);
            skippedAssets[0] = MC.AAVE_A_WSTETH;
            bool skip = false;
            for (uint256 i = 0; i < skippedAssets.length; ++i) {
                if (assets[assetIndex] == skippedAssets[i]) {
                    skip = true;
                    break;
                }
            }
            vm.assume(!skip);
        }

        address asset = assets[assetIndex];

        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < Math.min(100_000 ether, assetStakeLimit(asset)));

        address alice = address(0xa11ce);
        dealAsset(asset, alice, depositAmount);

        // Skip if asset is already active
        if (!vault.getAsset(asset).active) {
            vm.startPrank(address(timelock));
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(assetIndex, fields);
            vm.stopPrank();
        }

        vault.processAccounting();

        uint256 totalAssetBefore = vault.totalAssets();
        uint256 actualAmount = IERC20(asset).balanceOf(alice);
        uint256 vaultRateBefore = vault.convertToAssets(1e18);

        vm.startPrank(alice);
        IERC20(asset).approve(address(vault), actualAmount);
        vault.depositAsset(asset, actualAmount, address(this));
        vm.stopPrank();

        uint256 totalAssets = vault.totalAssets();
        uint256 assetRate = IProvider(vault.provider()).getRate(asset);
        uint256 vaultRateAfterDeposit = vault.convertToAssets(1e18);

        assertApproxEqRel(vaultRateBefore, vaultRateAfterDeposit, 1e10, "Vault rate should not change after deposit");

        assertApproxEqAbs(
            totalAssets,
            totalAssetBefore + (actualAmount * assetRate / 1e18),
            3,
            "Total assets should match deposit amount"
        );

        vault.processAccounting();

        uint256 vaultRateAfterProcessing = vault.convertToAssets(1e18);
        assertApproxEqRel(
            vaultRateAfterDeposit, vaultRateAfterProcessing, 1e10, "Vault rate should not change after processing"
        );

        // Verify total assets remains the same after processing accounting
        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetBefore + (actualAmount * assetRate / 1e18),
            3,
            "Total assets should match deposit amount"
        );
    }

    function testDepositOETHAndWithdraw(uint256 depositAmount) public {
        vm.assume(depositAmount > 1e9);
        vm.assume(depositAmount < 100_000 ether);
        uint256 depositAmountActual;
        address asset = MC.OETH;

        uint256 initialVaultOETH = IERC20(asset).balanceOf(address(vault));
        uint256 initialWithdrawerOETH = IERC20(asset).balanceOf(address(withdrawer));

        {
            address alice = makeAddr("alice");
            dealAsset(asset, alice, depositAmount);

            depositAmountActual = IERC20(asset).balanceOf(alice);

            {
                // Enable OETH as active asset using TIMELOCK
                vm.startPrank(TIMELOCK);
                vault.updateAsset(vault.getAsset(asset).index, IVault.AssetUpdateFields({active: true}));
                vm.stopPrank();
            }
            vm.startPrank(alice);
            IERC20(asset).approve(address(vault), depositAmountActual);
            vault.depositAsset(asset, depositAmountActual, alice);
            vm.stopPrank();
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 tvlBeforeWithdraw = vault.totalAssets();

        {
            // Approve and deposit OETH to withdrawer
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = asset;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(withdrawer), depositAmountActual));

            targets[1] = address(withdrawer);
            values[1] = 0;
            data[1] = abi.encodeCall(BaseVault.depositAsset, (MC.OETH, depositAmountActual, address(vault)));

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
                initialWithdrawerOETH + depositAmountActual,
                "Withdrawer OETH balance should match initial plus deposited amount"
            );
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        assertApproxEqRel(
            vault.totalAssets(), tvlBeforeWithdraw, 1e4, "Total assets should match after deposit to withdrawer"
        );

        uint256 tokenId;
        {
            vm.startPrank(PROCESSOR);
            tokenId = withdrawer.requestWithdrawalOETH(depositAmountActual);
            vm.stopPrank();

            assertEq(
                IERC20(asset).balanceOf(address(withdrawer)),
                initialWithdrawerOETH,
                "Withdrawer OETH balance should be back to initial amount"
            );

            assertEq(
                withdrawer.asyncWithdrawalBalance(MC.WOETH),
                depositAmountActual,
                "Async withdrawal balance for WOETH should match deposited amount"
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

        // TVL should remain unchanged since OETH was deposited and withdrawn
        assertApproxEqRel(
            vault.totalAssets(), tvlBeforeWithdraw, 1e4, "Total assets should remain unchanged after OETH withdrawal"
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

        assertApproxEqRel(
            tvlBeforeWithdraw, initialTotalAssets, 1e4, "Total assets should match before OETH withdrawal"
        );

        (uint256 withdrawerTotalAssetsBeforeClaim, uint256 woethRateBeforeClaim) =
            _claimWithdrawalWOETH(tokenId, depositAmountActual);

        uint256 woethRateAfterClaim = IERC4626(MC.WOETH).convertToAssets(1e18);

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

        {
            // WOETH rate increases both over time and at redemption time
            uint256 woethBalance = IERC20(MC.WOETH).balanceOf(address(withdrawer));
            uint256 rateDelta = woethRateAfterClaim - woethRateBeforeClaim;
            uint256 expectedTotalAssets = withdrawerTotalAssetsBeforeClaim + (woethBalance * rateDelta / 1e18);

            assertApproxEqRel(
                withdrawer.totalAssets(),
                expectedTotalAssets,
                1e3,
                "Withdrawer total assets should account for WOETH balance and rate changes"
            );
        }

        // The rates of underlying assets changes as time was advanced
        //,consequently the total assets changes slightly
        // computation factors in WOETH appreciation in the Withdrawer
        assertApproxEqRel(
            vault.totalAssets(),
            tvlBeforeWithdraw + withdrawer.totalAssets() - withdrawerTotalBefore,
            1e11,
            "Total assets should remain unchanged after processing accounting"
        );
    }

    function _claimWithdrawalWOETH(uint256 tokenId, uint256 donateAmount)
        internal
        returns (uint256 withdrawerTotalAssetsBeforeClaim, uint256 woethRateBeforeClaim)
    {
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

            // solhint-disable-next-line not-rely-on-time
            uint256 timestamp = block.timestamp;
            vm.warp(timestamp + oethVault.withdrawalClaimDelay() + 10 minutes);

            // Process accounting to reflect changes after passing of time to capture yield gains
            withdrawer.processAccounting();
            withdrawerTotalAssetsBeforeClaim = withdrawer.totalAssets();
            woethRateBeforeClaim = IERC4626(MC.WOETH).convertToAssets(1e18);

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

    function test_depositWstETH_requestWithdrawal(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e9, 10_000 ether);

        uint256 actualAmount;

        address asset = MC.WSTETH;

        {
            address alice = makeAddr("alice");
            // Enable wstETH as active asset using TIMELOCK
            vm.startPrank(address(timelock));
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(vault.getAsset(asset).index, fields);
            vm.stopPrank();

            // Process accounting
            withdrawer.processAccounting();
            vault.processAccounting();

            // Deal wstETH to alice and deposit to vault
            dealAsset(asset, alice, depositAmount);
            actualAmount = IERC20(asset).balanceOf(alice);

            vm.startPrank(alice);
            IERC20(asset).approve(address(vault), actualAmount);
            vault.depositAsset(asset, actualAmount, alice);
            vm.stopPrank();
        }

        // Process accounting
        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 withdrawerWstETHBefore = IERC20(asset).balanceOf(address(withdrawer));

        // Move wstETH from vault to withdrawer
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = asset;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(withdrawer), actualAmount));

            targets[1] = address(withdrawer);
            values[1] = 0;
            data[1] = abi.encodeCall(BaseVault.depositAsset, (asset, actualAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, data);
            vm.stopPrank();
        }

        // Verify wstETH was transferred to withdrawer
        assertEq(
            IERC20(asset).balanceOf(address(withdrawer)),
            withdrawerWstETHBefore + actualAmount,
            "wstETH should be transferred to withdrawer"
        );

        // Process accounting
        withdrawer.processAccounting();
        vault.processAccounting();
        uint256 asyncWithdrawalBalanceBefore = withdrawer.asyncWithdrawalBalance(asset);

        vm.startPrank(PROCESSOR);
        // Request withdrawal from withdrawer in chunks of max 1000 ether
        uint256 remainingAmount = actualAmount;
        uint256[] memory tokenIds = new uint256[](0);
        uint256 maxChunkSize = IwstETH(MC.WSTETH).getWstETHByStETH(1000 ether);

        while (remainingAmount > 0) {
            uint256 chunkAmount = remainingAmount > maxChunkSize ? maxChunkSize : remainingAmount;

            if (chunkAmount < 1e9) {
                // trim
                actualAmount -= chunkAmount;
                remainingAmount -= chunkAmount;
                break;
            }
            uint256 tokenId = WithdrawerProcessorUtils.processRequestWithdrawalWstETH(withdrawer, asset, chunkAmount);

            // Expand tokenIds array and add new tokenId
            uint256[] memory newTokenIds = new uint256[](tokenIds.length + 1);
            for (uint256 i = 0; i < tokenIds.length; i++) {
                newTokenIds[i] = tokenIds[i];
            }
            newTokenIds[tokenIds.length] = tokenId;
            tokenIds = newTokenIds;

            remainingAmount -= chunkAmount;
        }
        vm.stopPrank();

        assertApproxEqAbs(
            withdrawer.asyncWithdrawalBalance(asset) - asyncWithdrawalBalanceBefore,
            IwstETH(MC.WSTETH).getStETHByWstETH(actualAmount),
            10,
            "asyncWithdrawalBalance should increase by expected amount"
        );

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 fixedDelta = 2e3;

        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore,
            tokenIds.length > 0 ? tokenIds.length * fixedDelta : fixedDelta,
            "Total assets should remain the same after withdrawal request"
        );
        uint256 withdrawerETHBefore = address(withdrawer).balance;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            WithdrawerProcessorUtils.claimWithdrawalWstETH(withdrawer, PROCESSOR, tokenIds[i]);
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        assertApproxEqAbs(
            address(withdrawer).balance - withdrawerETHBefore,
            IwstETH(MC.WSTETH).getStETHByWstETH(actualAmount),
            fixedDelta,
            "ETH balance should increase by expected amount after withdrawal claim"
        );

        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore,
            tokenIds.length > 0 ? tokenIds.length * fixedDelta : fixedDelta,
            "Total assets should remain the same after withdrawal claim"
        );
    }

    function test_depositWETH_allocateToYnETH(uint256 depositAmount) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        // Process accounting
        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 vaultBalanceBefore = IERC20(MC.WETH).balanceOf(address(vault));
        uint256 ynEthBalanceBefore = IERC20(MC.YNETH).balanceOf(address(vault));

        // Deposit WETH to vault
        deal(MC.WETH, address(this), depositAmount);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.WETH, depositAmount, address(this));

        // Verify WETH was transferred to withdrawer
        assertEq(
            IERC20(MC.WETH).balanceOf(address(vault)),
            vaultBalanceBefore + depositAmount,
            "WETH should be transferred to vault"
        );

        // Process accounting
        withdrawer.processAccounting();
        vault.processAccounting();

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
        withdrawer.processAccounting();
        vault.processAccounting();

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
        uint256 depositAmount = 100 ether;

        address alice = makeAddr("alice");
        deal(MC.WETH, alice, 1000 ether);

        // Get initial balances
        uint256 aliceWethBalanceBefore = IERC20(MC.WETH).balanceOf(alice);
        uint256 vaultTotalAssetsBefore = vault.totalAssets();

        // Approve and deposit WETH
        vm.startPrank(alice);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit
        assertEq(
            IERC20(MC.WETH).balanceOf(alice),
            aliceWethBalanceBefore - depositAmount,
            "User WETH balance should decrease"
        );
        assertEq(vault.totalAssets(), vaultTotalAssetsBefore + depositAmount, "Vault total assets should increase");

        ProcessorUtils.allocateToBuffer(vault, depositAmount, PROCESSOR);

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

    function test_depositAndWithdrawFromBuffer_onBehalfOfUser() public {
        uint256 depositAmount = 100 ether;

        address alice = makeAddr("alice");
        deal(MC.WETH, alice, 1000 ether);

        // Get initial balances
        uint256 aliceWethBalanceBefore = IERC20(MC.WETH).balanceOf(alice);
        uint256 vaultTotalAssetsBefore = vault.totalAssets();

        // Approve and deposit WETH
        vm.startPrank(alice);
        IERC20(MC.WETH).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Verify deposit
        assertEq(
            IERC20(MC.WETH).balanceOf(alice),
            aliceWethBalanceBefore - depositAmount,
            "User WETH balance should decrease"
        );
        assertEq(vault.totalAssets(), vaultTotalAssetsBefore + depositAmount, "Vault total assets should increase");

        ProcessorUtils.allocateToBuffer(vault, depositAmount, PROCESSOR);

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
        {
            vm.startPrank(ADMIN);
            vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
            vm.stopPrank();

            uint256 index = vault.getAsset(MC.YNETH).index;
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(index, fields);

            index = vault.getAsset(MC.YNLSDE).index;
            fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(index, fields);
        }

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

            vault.processAccounting();
        }

        // Record total assets after deposits but before connector deposit
        uint256 totalAssetsAfterDeposits = vault.totalAssets();
        // Calculate TVL in terms of ynETH and ynLSDe rates
        uint256 ynEthRate = IProvider(vault.provider()).getRate(MC.YNETH);
        uint256 ynLsdeRate = IProvider(vault.provider()).getRate(MC.YNLSDE);

        uint256 ynEthValueInBase = depositAmount * ynEthRate / 1e18;
        uint256 ynLsdeValueInBase = depositAmount * ynLsdeRate / 1e18;

        assertApproxEqAbs(
            totalAssetsAfterDeposits - vaultTotalAssetsBefore,
            ynEthValueInBase + ynLsdeValueInBase,
            3,
            "Total assets increase should match sum of ynETH and ynLSDe values"
        );

        // Deposit equal amounts to ynETH and ynLSDe
        {
            address[] memory targets = new address[](3);
            uint256[] memory values = new uint256[](3);
            bytes[] memory data = new bytes[](3);

            // Approve and deposit to ynETH
            targets[0] = MC.YNETH;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR, depositAmount));

            targets[1] = MC.YNLSDE;
            values[1] = 0;
            data[1] = abi.encodeCall(IERC20.approve, (MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR, depositAmount));

            // Deposit to connector
            targets[2] = MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR;
            values[2] = 0;

            data[2] = abi.encodeWithSignature("deposit(uint256,uint256,uint256)", depositAmount, depositAmount, 0);
            // data[2] =  abi.encodeCall(ICurveLpConnector.deposit, (depositAmount, depositAmount, 0));

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, data);
            vm.stopPrank();
        }

        // Process accounting
        vault.processAccounting();

        // Verify balances
        assertApproxEqAbs(
            totalAssetsAfterDeposits - vaultTotalAssetsBefore,
            ynEthValueInBase + ynLsdeValueInBase,
            3,
            "Total assets increase should match sum of ynETH and ynLSDe values"
        );
    }
}

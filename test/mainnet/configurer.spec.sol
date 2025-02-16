// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {Vault} from "src/Vault.sol";
import {TimelockController, IERC20, Math} from "src/Common.sol";
import {MainnetActors, IActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {YnETHx} from "src/YnETHx.sol";
import {IVault} from "src/interface/IVault.sol";
import {YnETHxConfigurer} from "src/configures/YnETHxConfigurer.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {RolesVerification} from "script/verification/RolesVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";
import {BaseVault} from "src/BaseVault.sol";
import {IynETH} from "test/interface/external/yieldnest/IynETH.sol";
import {IWETH} from "test/interface/external/ethereum/IWETH.sol";

contract VaultConfigureUpgradeTest is Test, MainnetActors, AssertUtils {
    Vault public vault;
    Withdrawer public withdrawer;
    TimelockController public timelock;

    string public constant VAULT_VERSION = "0.2.0";

    function setUp() public {
        vault = Vault(payable(MC.YNETHX));
        timelock = TimelockController(payable(MC.TIMELOCK));
        uint256 previousTotalAssets = vault.totalAssets();

        {
            vm.expectRevert();
            vault.VAULT_VERSION();
        }

        _upgradeVault();

        assertEq(vault.symbol(), "ynETHx");

        assertTrue(vault.paused(), "Vault should be paused");

        YnETHxConfigurer configurer = new YnETHxConfigurer();
        SetupWithdrawer setup = new SetupWithdrawer();
        withdrawer = setup.setup();
        Provider provider = new Provider();

        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(configurer));

        configurer.configure(address(provider), address(withdrawer));
        vm.stopPrank();

        {
            // verify the upgrade was successful
            Vault newVault = Vault(payable(MC.YNETHX));

            assertFalse(newVault.paused(), "Vault should not be paused");

            newVault.processAccounting();

            // Verify the upgrade was successful
            uint256 newTotalAssets = newVault.totalAssets();

            assertEq(newTotalAssets, previousTotalAssets, "Total assets should remain the same after upgrade");
            assertEq(
                keccak256(bytes(vault.VAULT_VERSION())),
                keccak256(bytes(VAULT_VERSION)),
                "Vault version should be correct"
            );
        }
    }

    function _upgradeVault() internal {
        // upgrade the vault
        Vault vaultImpl = Vault(payable(new YnETHx()));

        // schedule a proxy upgrade transaction on the timelock
        // the traget is the proxy admin for the max Vault Proxy Contract
        address target = MC.PROXY_ADMIN;
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

        bytes memory initData = abi.encodeWithSelector(YnETHx.initializeV2.selector, 18, 0);
        bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(vaultImpl), initData);

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");

        uint256 delay = 86400;

        vm.startPrank(PROPOSER_1);
        timelock.schedule(target, value, data, predecessor, salt, delay);
        vm.stopPrank();

        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
        assert(timelock.getOperationState(id) == TimelockController.OperationState.Waiting);

        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);
        assertEq(timelock.isOperation(id), true);

        //execute the transaction
        // solhint-disable-next-line not-rely-on-time
        vm.warp(block.timestamp + 86401);
        vm.startPrank(EXECUTOR_1);
        timelock.execute(target, value, data, predecessor, salt);
        vm.stopPrank();

        // Verify the transaction was executed successfully
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), true);
        assert(timelock.getOperationState(id) == TimelockController.OperationState.Done);
    }

    function test_configure() public view {
        // verify the configuration was successful
        IActors actors = IActors(payable(address(this)));

        VaultVerification.verifyProvider(Provider(IVault(address(vault)).provider()), withdrawer);

        VaultVerification.verifyVaultConfiguration(vault, withdrawer);

        VaultVerification.verifyRules(vault);

        // verify actors & timelock roles on vault
        RolesVerification.verifyDefaultRoles(vault, timelock, actors);
        RolesVerification.verifyRole(
            vault, actors.FEE_MANAGER(), vault.FEE_MANAGER_ROLE(), true, "Fee Manager has FEE_MANAGER_ROLE"
        );

        // verify proxy roles on vault
        RolesVerification.verifyProxyRoles(address(vault), MC.PROXY_ADMIN, address(timelock));

        // verify withdrawer config
        VaultVerification.verifyWithdrawerConfiguration(vault, withdrawer);

        // verify withdrawer roles
        VaultVerification.verifyWithdrawerRules(withdrawer);

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

        deal(MC.YNETH, address(this), depositAmount);
        uint256 totalAssetBefore = vault.totalAssets();

        IERC20(MC.YNETH).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNETH, depositAmount, address(this));
        vault.processAccounting();

        uint256 totalAssets = vault.totalAssets();
        uint256 ynEthRate = IProvider(vault.provider()).getRate(MC.YNETH);

        assertApproxEqRel(
            totalAssets,
            totalAssetBefore + (depositAmount * ynEthRate / 1e18),
            1e16, // Keep original small threshold
            "Total assets should match deposit amount"
        );
    }

    function test_deposit_ynLSDe(uint256 depositAmount) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        uint256 totalAssetBefore = vault.totalAssets();

        // Deposit YNLSDE
        deal(MC.YNLSDE, address(this), depositAmount);
        IERC20(MC.YNLSDE).approve(address(vault), depositAmount);
        vault.depositAsset(MC.YNLSDE, depositAmount, address(this));

        vault.processAccounting();

        // Assert totalAssets is correct
        uint256 totalAssets = vault.totalAssets();

        uint256 ynLSDeRate = IProvider(vault.provider()).getRate(MC.YNLSDE);
        assertApproxEqRel(
            totalAssets,
            totalAssetBefore + (depositAmount * ynLSDeRate / 1e18),
            1e16,
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
        assertApproxEqRel(
            totalAssets,
            totalAssetBefore + (depositAmount * wethRate / 1e18),
            1e16,
            "Total assets should match deposit amount"
        );
    }

    function dealAsset(address asset, address account, uint256 amount) internal {
        if (asset == MC.STETH) {
            vm.deal(account, amount);

            vm.startPrank(account);
            (bool success,) = MC.STETH.call{value: amount}("");
            vm.stopPrank();

            assertTrue(success, "stETH deposit failed");
            return;
        }

        if (asset == MC.OETH) {
            deal(MC.WETH, account, amount);

            vm.startPrank(account);
            IERC20(MC.WETH).approve(MC.OETH_VAULT, amount);
            IOETHVault(MC.OETH_VAULT).mint(MC.WETH, amount, amount);
            vm.stopPrank();
            return;
        }

        deal(asset, account, amount);
    }

    function test_donate_assets(uint256 donationAmount) public {
        vm.assume(donationAmount > 1e8);
        vm.assume(donationAmount < 1_000 ether);

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 11, "Should have 11 assets");

        for (uint256 i = 0; i < assets.length; i++) {
            _test_donate_single_asset(assets[i], donationAmount);
        }
    }

    function _test_donate_single_asset(address asset, uint256 donationAmount) internal {
        address alice = address(0xa11ce);

        uint256 totalAssetBefore = vault.totalAssets();

        assertEq(IERC20(asset).balanceOf(alice), 0, "Balance should be 0 before donation");

        dealAsset(asset, alice, donationAmount);

        uint256 donatedAmount = IERC20(asset).balanceOf(alice);

        // The donation function does not donate the full amount. Must use the actual donated amount after.
        assertApproxEqRel(donatedAmount, donationAmount, 1e14, "Balance should match for asset");

        vm.startPrank(alice);
        IERC20(asset).transfer(address(vault), donatedAmount);
        vm.stopPrank();

        vault.processAccounting();

        uint256 rate = IProvider(vault.provider()).getRate(asset);
        uint256 baseAmount = Math.mulDiv(donatedAmount, rate, 10 ** 18, Math.Rounding.Floor);

        assertApproxEqRel(vault.totalAssets(), totalAssetBefore + baseAmount, 1e8, "Total assets should be correct");
    }

    function test_deposit_any_asset(uint256 depositAmount, uint8 assetIndex) public {
        vm.assume(depositAmount > 10000);
        vm.assume(depositAmount < 100_000 ether);

        address[] memory assets = vault.getAssets();
        vm.assume(assetIndex < assets.length);
        address asset = assets[assetIndex];

        dealAsset(asset, address(this), depositAmount);

        // Skip if asset is already active
        if (!vault.getAsset(asset).active) {
            vm.startPrank(address(timelock));
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(assetIndex, fields);
            vm.stopPrank();
        }

        uint256 totalAssetBefore = vault.totalAssets();
        uint256 actualAmount = IERC20(asset).balanceOf(address(this));
        uint256 vaultRateBefore = vault.convertToAssets(1e18);

        IERC20(asset).approve(address(vault), actualAmount);
        vault.depositAsset(asset, actualAmount, address(this));

        uint256 totalAssets = vault.totalAssets();
        uint256 assetRate = IProvider(vault.provider()).getRate(asset);
        uint256 vaultRateAfterDeposit = vault.convertToAssets(1e18);

        assertEq(vaultRateBefore, vaultRateAfterDeposit, "Vault rate should not change after deposit");

        assertApproxEqRel(
            totalAssets,
            totalAssetBefore + (actualAmount * assetRate / 1e18),
            1e8,
            "Total assets should match deposit amount"
        );

        vault.processAccounting();

        uint256 vaultRateAfterProcessing = vault.convertToAssets(1e18);
        assertEq(vaultRateAfterDeposit, vaultRateAfterProcessing, "Vault rate should not change after processing");

        // Verify total assets remains the same after processing accounting
        assertApproxEqRel(
            vault.totalAssets(),
            totalAssetBefore + (actualAmount * assetRate / 1e18),
            1e8,
            "Total assets should match deposit amount"
        );
    }

    function testDonateOETHAndWithdraw() public {
        uint256 donationAmount = 100e18;
        uint256 donateAmount;
        address asset = MC.OETH;

        uint256 initialVaultOETH = IERC20(asset).balanceOf(address(vault));
        uint256 initialWithdrawerOETH = IERC20(asset).balanceOf(address(withdrawer));

        address alice = makeAddr("alice");
        {
            dealAsset(asset, alice, donationAmount);

            donateAmount = IERC20(asset).balanceOf(alice);

            // The donation function does not donate the full amount. Must use the actual donated amount after.
            assertApproxEqRel(donateAmount, donationAmount, 1e14, "Balance should match for asset");

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

        vault.processAccounting();

        assertApproxEqRel(
            vault.totalAssets(), tvlBeforeWithdraw, 0, "Total assets should match after deposit to withdrawer"
        );

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
                withdrawer.asyncWithdrawalBalance(MC.OETH),
                0,
                "Async withdrawal balance for WOETH should match donated amount"
            );
        }

        withdrawer.processAccounting();
        // Process accounting to reflect changes
        vault.processAccounting();

        // TVL should remain unchanged since OETH was donated and withdrawn
        assertApproxEqRel(
            vault.totalAssets(), tvlBeforeWithdraw, 1e8, "Total assets should remain unchanged after OETH withdrawal"
        );

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
                deal(MC.WETH, MC.OETH_VAULT, outstandingWithdrawals + donateAmount);

                assertEq(
                    weth.balanceOf(MC.OETH_VAULT), donateAmount + outstandingWithdrawals, "WETH balance should match"
                );

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

            assertEq(
                IERC20(asset).balanceOf(address(vault)),
                initialVaultOETH,
                "Vault OETH balance should match initial balance"
            );
        }

        // Process accounting and verify total assets remain unchanged
        vault.processAccounting();
        withdrawer.processAccounting();

        assertApproxEqRel(
            vault.totalAssets(),
            tvlBeforeWithdraw,
            1e8,
            "Total assets should remain unchanged after processing accounting"
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
            vault.processor(targets, values, data);
            vm.stopPrank();
        }

        // Process accounting
        vault.processAccounting();
        withdrawer.processAccounting();

        // Get ynETH rate
        uint256 ynEthRate = IProvider(vault.provider()).getRate(MC.YNETH);

        // Verify total assets increased by correct amount
        assertApproxEqRel(
            vault.totalAssets(),
            totalAssetsBefore + depositAmount,
            1e8,
            "Total assets should match deposit amount converted to ynETH"
        );

        // Verify ynETH balance matches expected amount based on rate
        assertApproxEqRel(
            IERC20(MC.YNETH).balanceOf(address(vault)),
            ynEthBalanceBefore + (depositAmount * 1e18) / ynEthRate,
            1e8,
            "ynETH balance should match expected amount based on rate"
        );
    }
}

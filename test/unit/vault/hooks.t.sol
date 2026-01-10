// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockSTETH} from "test/unit/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {FeeHooks} from "src/hooks/FeeHooks.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "src/Common.sol";
import {console} from "lib/forge-std/src/console.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {TestHelpers} from "test/unit/helpers/TestHelpers.sol";
import {MockNoOpHooks} from "test/unit/mocks/MockNoOpHooks.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

contract HooksUnitTest is Test, MainnetActors, Etches, AssertUtils {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;

    WETH9 public weth;
    MockSTETH public steth;
    IHooks public hooks;

    address public alice = address(0x1);
    address public caller = address(0x2);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();
        hooks = MockNoOpHooks(address(vault.hooks()));

        vm.prank(ADMIN);
        vault.setHooks(address(hooks));

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(MC.STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        deal(caller, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(caller, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        vm.prank(caller);
        weth.approve(address(vault), type(uint256).max);
    }

    function test_afterRedeem_NoChangeInShares(uint256 sharesAmount) public {
        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);

        sharesAmount = bound(sharesAmount, 0.001 ether, 100_000 ether);
        vm.startPrank(alice);
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: sharesAmount,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase");
    }

    function test_afterRedeem_ExemptedFromFee(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, 0, true);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: shares,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase due to fee exemption");
    }

    function test_afterRedeem_OverriddenFee(uint256 depositAmount, uint64 overriddenFee) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: shares,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase due to fee overriden");
    }

    function test_beforeWithdraw_NoChangeInShares(uint256 sharesAmount) public {
        vm.prank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);

        sharesAmount = bound(sharesAmount, 0.001 ether, 100_000 ether);
        vm.startPrank(alice);
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: sharesAmount,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase by sharesAmount");
    }

    function test_beforeWithdraw_ExemptedFromFee(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, 0, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: depositAmount,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should not increase due to fee exemption");
    }

    function test_beforeWithdraw_OverriddenFee(uint256 depositAmount, uint64 overriddenFee) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        overriddenFee = uint64(bound(overriddenFee, 2500, FeeMath.BASIS_POINT_SCALE));
        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(250000);
        vault.overrideBaseWithdrawalFee(alice, overriddenFee, true);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: depositAmount,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        assertEq(totalSupplyAfter, totalSupplyBefore, "totalSupply should increase due to fee overriden");
    }

    function test_beforeWithdraw_MintsToFeeRecipient(
        uint256 depositAmount,
        uint256 yieldAmount,
        uint256 withdrawalAmount,
        uint64 withdrawalFee
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        yieldAmount = bound(yieldAmount, 1 ether, 100 ether);
        withdrawalAmount = bound(withdrawalAmount, 10000, depositAmount - 1000);
        withdrawalFee = uint64(bound(withdrawalFee, 0, 1e8 / 2));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);
        vm.stopPrank();

        vm.startPrank(alice);
        vault.deposit(depositAmount, alice);
        weth.transfer(address(vault), yieldAmount);
        vault.processAccounting();
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        vm.startPrank(address(vault));
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: withdrawalAmount,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 sharesMinted = vaultBalanceOfPerformanceFeeRecipientAfter - vaultBalanceOfPerformanceFeeRecipientBefore;

        assertEq(totalSupplyAfter, totalSupplyBefore + sharesMinted, "total supply should increase by shares minted");
    }

    function test_afterRedeem_MintsToFeeRecipient(
        uint256 depositAmount,
        uint256 yieldAmount,
        uint256 withdrawalAmount,
        uint64 withdrawalFee
    ) public {
        depositAmount = bound(depositAmount, 1 ether, 100_000 ether);
        yieldAmount = bound(yieldAmount, 1 ether, 100 ether);
        withdrawalAmount = bound(withdrawalAmount, 10000, depositAmount - 1000);
        withdrawalFee = uint64(bound(withdrawalFee, 0, 1e8 / 2));

        vm.startPrank(FEE_MANAGER);
        vault.setBaseWithdrawalFee(withdrawalFee);
        vm.stopPrank();

        vm.startPrank(alice);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientBefore =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());

        vm.startPrank(address(vault));
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: shares,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        vm.stopPrank();

        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 vaultBalanceOfPerformanceFeeRecipientAfter =
            vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
        uint256 sharesMinted = vaultBalanceOfPerformanceFeeRecipientAfter - vaultBalanceOfPerformanceFeeRecipientBefore;

        assertEq(totalSupplyAfter, totalSupplyBefore + sharesMinted, "total supply should increase by shares minted");
    }

    function test_AfterProcessAccounting_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1 ether,
                totalAssetsAfterAccounting: 1 ether,
                totalSupplyBeforeAccounting: 1 ether,
                totalSupplyAfterAccounting: 1 ether,
                totalBaseAssetsBeforeAccounting: 1 ether,
                totalBaseAssetsAfterAccounting: 1 ether
            })
        );
        vm.stopPrank();
    }

    function test_beforeWithdraw_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        vm.stopPrank();
    }

    function test_afterRedeem_NotCalledByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        vm.stopPrank();
    }

    function test_HooksFunction_OnlyCallableByVault() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeDeposit(
            IHooks.DepositParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                shares: 0,
                baseAssets: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterDeposit(
            IHooks.DepositParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                shares: 0,
                baseAssets: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeMint(
            IHooks.MintParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                assets: 0,
                baseAssets: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterMint(
            IHooks.MintParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                assets: 0,
                baseAssets: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.beforeProcessAccounting(
            IHooks.BeforeProcessAccountingParams({
                totalAssetsBeforeAccounting: 1 ether,
                totalSupplyBeforeAccounting: 1 ether,
                totalBaseAssetsBeforeAccounting: 1 ether
            })
        );

        vm.expectRevert(abi.encodeWithSelector(IHooks.CallerNotVault.selector));
        hooks.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1 ether,
                totalAssetsAfterAccounting: 1 ether,
                totalSupplyBeforeAccounting: 1 ether,
                totalSupplyAfterAccounting: 1 ether,
                totalBaseAssetsBeforeAccounting: 1 ether,
                totalBaseAssetsAfterAccounting: 1 ether
            })
        );
        vm.stopPrank();

        vm.startPrank(address(vault));
        hooks.beforeDeposit(
            IHooks.DepositParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                shares: 0,
                baseAssets: 0
            })
        );
        hooks.afterDeposit(
            IHooks.DepositParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                shares: 0,
                baseAssets: 0
            })
        );
        hooks.beforeMint(
            IHooks.MintParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                assets: 0,
                baseAssets: 0
            })
        );
        hooks.afterMint(
            IHooks.MintParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                assets: 0,
                baseAssets: 0
            })
        );
        hooks.beforeRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        hooks.afterRedeem(
            IHooks.RedeemParams({
                asset: MC.WETH,
                shares: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                assets: 0
            })
        );
        hooks.beforeWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        hooks.afterWithdraw(
            IHooks.WithdrawParams({
                asset: MC.WETH,
                assets: 1 ether,
                caller: alice,
                receiver: alice,
                owner: alice,
                shares: 0
            })
        );
        hooks.beforeProcessAccounting(
            IHooks.BeforeProcessAccountingParams({
                totalAssetsBeforeAccounting: 1 ether,
                totalSupplyBeforeAccounting: 1 ether,
                totalBaseAssetsBeforeAccounting: 1 ether
            })
        );
        hooks.afterProcessAccounting(
            IHooks.AfterProcessAccountingParams({
                totalAssetsBeforeAccounting: 1 ether,
                totalAssetsAfterAccounting: 1 ether,
                totalSupplyBeforeAccounting: 1 ether,
                totalSupplyAfterAccounting: 1 ether,
                totalBaseAssetsBeforeAccounting: 1 ether,
                totalBaseAssetsAfterAccounting: 1 ether
            })
        );
        vm.stopPrank();
    }

    function test_depositHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: true,
                afterDeposit: true,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeDeposit and afterDeposit to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeDeposit,
                (
                    IHooks.DepositParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: caller,
                        receiver: alice,
                        shares: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterDeposit,
                (
                    IHooks.DepositParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: caller,
                        receiver: alice,
                        shares: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            1
        );
        vault.deposit(1 ether, alice);
        vm.stopPrank();
    }

    function test_depositAssetHooks_Enabled(uint8 assetIndex) public {
        address[] memory activeAssets = TestHelpers.getActiveAssets(vault);
        vm.assume(activeAssets.length > 0);
        vm.assume(assetIndex < activeAssets.length);

        // Use the asset at the given index
        address asset = activeAssets[assetIndex];

        // Setup caller with the selected asset
        if (asset == MC.WETH) {
            // Already set up in setUp()
        } else {
            // Deal tokens for other assets
            deal(asset, caller, INITIAL_BALANCE);
        }

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: true,
                afterDeposit: true,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        uint256 depositAmount = 1 ether;
        uint256 sharesAmount = vault.previewDepositAsset(asset, depositAmount);
        uint256 baseAssetAmount = vault.convertToAssets(sharesAmount);

        vm.startPrank(caller);
        // Approve the vault to spend the asset
        IERC20(asset).approve(address(vault), 1 ether);
        // expect beforeDeposit and afterDeposit to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeDeposit,
                (
                    IHooks.DepositParams({
                        asset: asset,
                        assets: depositAmount,
                        caller: caller,
                        receiver: alice,
                        shares: sharesAmount,
                        baseAssets: baseAssetAmount
                    })
                )
            ),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterDeposit,
                (
                    IHooks.DepositParams({
                        asset: asset,
                        assets: depositAmount,
                        caller: caller,
                        receiver: alice,
                        shares: sharesAmount,
                        baseAssets: baseAssetAmount
                    })
                )
            ),
            1
        );
        vault.depositAsset(asset, depositAmount, alice);
        vm.stopPrank();
    }

    function test_depositHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeDeposit and afterDeposit to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeDeposit,
                (
                    IHooks.DepositParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: caller,
                        receiver: alice,
                        shares: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterDeposit,
                (
                    IHooks.DepositParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: caller,
                        receiver: alice,
                        shares: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            0
        );
        vault.deposit(1 ether, alice);
        vm.stopPrank();
    }

    function test_depositAssetHooks_Disabled(uint8 assetIndex) public {
        // Get all assets and filter for active ones
        address[] memory activeAssets = TestHelpers.getActiveAssets(vault);
        vm.assume(activeAssets.length > 0);
        vm.assume(assetIndex < activeAssets.length);

        address asset = activeAssets[assetIndex];

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        // Setup caller with the selected asset
        if (asset == MC.WETH) {
            // Already set up in setUp()
        } else {
            // Deal tokens for other assets
            deal(asset, caller, INITIAL_BALANCE);
        }

        uint256 depositAmount = 1 ether;
        uint256 sharesAmount = vault.previewDepositAsset(asset, depositAmount);
        uint256 baseAssetAmount = vault.convertToAssets(sharesAmount);

        vm.startPrank(caller);

        // Approve the vault to spend the asset
        IERC20(asset).approve(address(vault), depositAmount);
        // expect beforeDeposit and afterDeposit to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeDeposit,
                (
                    IHooks.DepositParams({
                        asset: asset,
                        assets: depositAmount,
                        caller: caller,
                        receiver: alice,
                        shares: sharesAmount,
                        baseAssets: baseAssetAmount
                    })
                )
            ),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterDeposit,
                (
                    IHooks.DepositParams({
                        asset: asset,
                        assets: depositAmount,
                        caller: caller,
                        receiver: alice,
                        shares: sharesAmount,
                        baseAssets: baseAssetAmount
                    })
                )
            ),
            0
        );
        vault.depositAsset(asset, depositAmount, alice);
        vm.stopPrank();
    }

    function test_mintHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: true,
                afterMint: true,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeMint and afterMint to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeMint,
                (
                    IHooks.MintParams({
                        asset: MC.WETH,
                        shares: 1 ether,
                        caller: caller,
                        receiver: alice,
                        assets: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterMint,
                (
                    IHooks.MintParams({
                        asset: MC.WETH,
                        shares: 1 ether,
                        caller: caller,
                        receiver: alice,
                        assets: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            1
        );
        vault.mint(1 ether, alice);
        vm.stopPrank();
    }

    function test_mintHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        // expect beforeMint and afterMint to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeMint,
                (
                    IHooks.MintParams({
                        asset: MC.WETH,
                        shares: 1 ether,
                        caller: caller,
                        receiver: alice,
                        assets: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterMint,
                (
                    IHooks.MintParams({
                        asset: MC.WETH,
                        shares: 1 ether,
                        caller: caller,
                        receiver: alice,
                        assets: 1 ether,
                        baseAssets: 1 ether
                    })
                )
            ),
            0
        );
        vault.mint(1 ether, alice);
        vm.stopPrank();
    }

    function test_redeemHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: true,
                afterRedeem: true,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.prank(caller);
        uint256 depositShares = vault.deposit(1 ether, alice);

        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        uint256 sharesToRedeem = depositShares;
        uint256 assetsToRedeem = vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeRedeem and afterRedeem to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeRedeem,
                (
                    IHooks.RedeemParams({
                        asset: MC.WETH,
                        shares: sharesToRedeem,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        assets: assetsToRedeem
                    })
                )
            ),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterRedeem,
                (
                    IHooks.RedeemParams({
                        asset: MC.WETH,
                        shares: sharesToRedeem,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        assets: assetsToRedeem
                    })
                )
            ),
            1
        );
        vault.redeem(sharesToRedeem, alice, alice);
        vm.stopPrank();
    }

    function test_redeemHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.prank(caller);
        uint256 depositShares = vault.deposit(1 ether, alice);

        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        uint256 sharesToRedeem = depositShares;
        vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeRedeem and afterRedeem to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeRedeem,
                (
                    IHooks.RedeemParams({
                        asset: MC.WETH,
                        shares: 1 ether,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        assets: 1 ether
                    })
                )
            ),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterRedeem,
                (
                    IHooks.RedeemParams({
                        asset: MC.WETH,
                        shares: 1 ether,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        assets: 1 ether
                    })
                )
            ),
            0
        );
        vault.redeem(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_withdrawHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: true,
                afterWithdraw: true,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        uint256 depositShares = vault.deposit(1 ether, alice);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        uint256 sharesToRedeem = depositShares;
        vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeWithdraw,
                (
                    IHooks.WithdrawParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        shares: 1 ether
                    })
                )
            ),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterWithdraw,
                (
                    IHooks.WithdrawParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        shares: 1 ether
                    })
                )
            ),
            1
        );
        vault.withdraw(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_withdrawHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        uint256 depositShares = vault.deposit(1 ether, alice);
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        uint256 sharesToRedeem = depositShares;
        vault.previewRedeem(sharesToRedeem);

        vm.startPrank(alice);
        // expect beforeWithdraw and afterWithdraw to not be called
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeWithdraw,
                (
                    IHooks.WithdrawParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        shares: 1 ether
                    })
                )
            ),
            0
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterWithdraw,
                (
                    IHooks.WithdrawParams({
                        asset: MC.WETH,
                        assets: 1 ether,
                        caller: alice,
                        receiver: alice,
                        owner: alice,
                        shares: 1 ether
                    })
                )
            ),
            0
        );
        vault.withdraw(1 ether, alice, alice);
        vm.stopPrank();
    }

    function test_processAccountingHooks_Enabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: true,
                afterProcessAccounting: true
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        // expect beforeProcessAccounting and afterProcessAccounting to be called by 1 time
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.beforeProcessAccounting,
                (
                    IHooks.BeforeProcessAccountingParams({
                        totalAssetsBeforeAccounting: 1 ether,
                        totalSupplyBeforeAccounting: 1 ether,
                        totalBaseAssetsBeforeAccounting: 1 ether
                    })
                )
            ),
            1
        );
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterProcessAccounting,
                (
                    IHooks.AfterProcessAccountingParams({
                        totalAssetsBeforeAccounting: 1 ether,
                        totalAssetsAfterAccounting: 1 ether,
                        totalSupplyBeforeAccounting: 1 ether,
                        totalSupplyAfterAccounting: 1 ether,
                        totalBaseAssetsBeforeAccounting: 1 ether,
                        totalBaseAssetsAfterAccounting: 1 ether
                    })
                )
            ),
            1
        );
        vault.processAccounting();
        vm.stopPrank();
    }

    function test_processAccountingHooks_Enabled_with_yield() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: true,
                afterProcessAccounting: true
            })
        );
        vm.stopPrank();

        uint256 depositAmount = 1 ether;

        vm.startPrank(caller);
        uint256 mintedShares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        uint256 donationAmount = 0.1 ether;
        {
            // Add yield to the vault
            address donor = address(0x999);
            deal(donor, donationAmount);
            vm.startPrank(donor);
            weth.deposit{value: donationAmount}();
            weth.transfer(address(vault), donationAmount);
            vm.stopPrank();
        }

        {
            // expect beforeProcessAccounting to be called by 1 time
            vm.expectCall(
                address(hooks),
                abi.encodeCall(
                    IHooks.beforeProcessAccounting,
                    (
                        IHooks.BeforeProcessAccountingParams({
                            totalAssetsBeforeAccounting: depositAmount, // totalAssetsBefore
                            totalSupplyBeforeAccounting: mintedShares, // totalSupplyBefore
                            totalBaseAssetsBeforeAccounting: depositAmount // totalBaseAssetsBefore
                        })
                    )
                ),
                1
            );
        }

        {
            uint256 expectedTotalAssetsAfter = depositAmount + donationAmount;
            uint256 expectedTotalSupplyAfter = mintedShares;
            uint256 expectedTotalBaseAssetsAfter = expectedTotalAssetsAfter;
            // Expect afterProcessAccounting hook to be called exactly once
            vm.expectCall(
                address(hooks),
                abi.encodeCall(
                    IHooks.afterProcessAccounting,
                    (
                        IHooks.AfterProcessAccountingParams({
                            totalAssetsBeforeAccounting: depositAmount, // totalAssetsBefore
                            totalAssetsAfterAccounting: expectedTotalAssetsAfter, // totalAssetsAfter
                            totalSupplyBeforeAccounting: mintedShares, // totalSupplyBefore
                            totalSupplyAfterAccounting: expectedTotalSupplyAfter, // totalSupplyAfter
                            totalBaseAssetsBeforeAccounting: depositAmount, // totalBaseAssetsBefore
                            totalBaseAssetsAfterAccounting: expectedTotalBaseAssetsAfter // totalBaseAssetsAfter
                        })
                    )
                ),
                1 // call count
            );
        }
        vault.processAccounting();
        vm.stopPrank();
    }

    function test_processAccountingHooks_Disabled() public {
        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: false,
                afterDeposit: false,
                beforeMint: false,
                afterMint: false,
                beforeRedeem: false,
                afterRedeem: false,
                beforeWithdraw: false,
                afterWithdraw: false,
                beforeProcessAccounting: false,
                afterProcessAccounting: false
            })
        );
        vm.stopPrank();

        vm.startPrank(caller);
        vault.deposit(1 ether, alice);
        vm.stopPrank();

        // expect beforeProcessAccounting and afterProcessAccounting to not be called
        // Expect beforeProcessAccounting hook to not be called when hooks are disabled
        vm.expectCall(
            address(hooks), // hooks contract address
            abi.encodeCall(
                IHooks.beforeProcessAccounting, // function selector
                (
                    IHooks.BeforeProcessAccountingParams({
                        totalAssetsBeforeAccounting: 1 ether, // totalAssetsBefore
                        totalSupplyBeforeAccounting: 1 ether, // totalSupplyBefore
                        totalBaseAssetsBeforeAccounting: 1 ether // totalSupplyBefore
                    })
                )
            ),
            0 // call count - should not be called since hooks are disabled
        );
        // Expect afterProcessAccounting hook to not be called when hooks are disabled
        vm.expectCall(
            address(hooks),
            abi.encodeCall(
                IHooks.afterProcessAccounting,
                (
                    IHooks.AfterProcessAccountingParams({
                        totalAssetsBeforeAccounting: 1 ether, // totalAssetsBefore
                        totalAssetsAfterAccounting: 1 ether, // totalAssetsAfter
                        totalSupplyBeforeAccounting: 1 ether, // totalSupplyBefore
                        totalSupplyAfterAccounting: 1 ether, // totalSupplyAfter
                        totalBaseAssetsBeforeAccounting: 1 ether, // totalBaseAssetsBefore
                        totalBaseAssetsAfterAccounting: 1 ether // totalBaseAssetsAfter
                    })
                )
            ),
            0 // call count - should not be called
        );
        vault.processAccounting();
        vm.stopPrank();
    }

    function test_HooksAllSet() public {
        vm.prank(ADMIN);
        vault.setHooks(address(hooks));

        vm.startPrank(HOOKS_MANAGER);
        hooks.setConfig(
            IHooks.Config({
                beforeDeposit: true,
                afterDeposit: true,
                beforeMint: true,
                afterMint: true,
                beforeRedeem: true,
                afterRedeem: true,
                beforeWithdraw: true,
                afterWithdraw: true,
                beforeProcessAccounting: true,
                afterProcessAccounting: true
            })
        );
        vm.stopPrank();

        // expect all of the hooks to be called
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeDeposit.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterDeposit.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeMint.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterMint.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeRedeem.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterRedeem.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeWithdraw.selector), 1);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterWithdraw.selector), 1);

        // called twice, once by allocateToBuffer and once by processAccounting
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeProcessAccounting.selector), 2);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterProcessAccounting.selector), 2);

        vm.startPrank(caller);
        vault.deposit(1 ether, alice);
        vault.mint(1 ether, alice);
        vm.stopPrank();
        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        vault.processAccounting();

        vm.startPrank(alice);
        vault.redeem(1 wei, alice, alice);
        vault.withdraw(1 wei, alice, alice);
        vm.stopPrank();
    }

    function test_HooksNotSet() public {
        vm.prank(ADMIN);
        vault.setHooks(address(0));

        // expect none of the hooks to not be called
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeDeposit.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterDeposit.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeMint.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterMint.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeRedeem.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterRedeem.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeWithdraw.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterWithdraw.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.beforeProcessAccounting.selector), 0);
        vm.expectCall(address(hooks), abi.encodeWithSelector(IHooks.afterProcessAccounting.selector), 0);

        vm.startPrank(caller);
        vault.deposit(1 ether, alice);
        vault.mint(1 ether, alice);
        vm.stopPrank();
        ProcessorUtils.allocateToBuffer(vault, 1 ether, PROCESSOR);

        vault.processAccounting();

        vm.startPrank(alice);
        vault.redeem(1 wei, alice, alice);
        vault.withdraw(1 wei, alice, alice);
        vm.stopPrank();
    }

    function test_setHooks_revertsIfInvalidHooks() public {
        SetupVault setupVault = new SetupVault();
        (Vault dummyVault,) = setupVault.setup();
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });
        address invalidHooks = address(new FeeHooks(address(dummyVault), ADMIN, 1e17, FEE_MANAGER, config));
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(IVault.InvalidHooks.selector));
        vault.setHooks(invalidHooks);
    }

    function test_setHooks_ZeroAddress() public {
        vm.startPrank(ADMIN);
        vault.setHooks(address(0));
        assertEq(address(vault.hooks()), address(0));
    }

    function test_Vault_setHooks_zeroAddress() public {
        vm.prank(HOOKS_MANAGER);
        vault.setHooks(address(0));

        assertEq(address(vault.hooks()), address(0), "Hooks should be set to zero address");
    }

    function test_Vault_setHooks_emitsEvent() public {
        MockNoOpHooks newHooks = new MockNoOpHooks(vault);

        vm.expectEmit(true, true, false, false);
        emit IVault.SetHooks(address(vault.hooks()), address(newHooks));

        vm.prank(HOOKS_MANAGER);
        vault.setHooks(address(newHooks));
    }

    function test_Vault_setHooks_revertsWhenInvalidHooks() public {
        // Create hooks for a different vault
        Vault implementation = new Vault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        Vault otherVault = Vault(payable(address(proxy)));
        otherVault.initialize(address(this), "Other", "OTH", 18, 0, false, false, 0);

        MockNoOpHooks invalidHooks = new MockNoOpHooks(otherVault);

        vm.expectRevert(IVault.InvalidHooks.selector);
        vm.prank(HOOKS_MANAGER);
        vault.setHooks(address(invalidHooks));
    }

    function test_Vault_setHooks_unauthorized() public {
        MockNoOpHooks newHooks = new MockNoOpHooks(vault);

        vm.expectRevert();
        vault.setHooks(address(newHooks));
    }
}

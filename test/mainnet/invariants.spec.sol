// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20, TransparentUpgradeableProxy, IERC4626, Math} from "src/Common.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {console} from "forge-std/console.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";

contract VaultMainnetInvariantsTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;

    Withdrawer public withdrawer;

    IProvider public provider;
    address public user = makeAddr("user");

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        provider = IProvider(vault.provider());

        withdrawer = VaultVerification.getWithdrawer(vault);
        assertEq(vault.asset(), MC.WETH, "base asset should be weth");

        assertEq(vault.baseWithdrawalFee(), 250000, "base withdrawal fee should be correct");

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function _convertAssetToBase(address asset_, uint256 assets) internal view returns (uint256) {
        uint256 rate = provider.getRate(asset_);
        return assets.mulDiv(rate, 10 ** 18, Math.Rounding.Floor);
    }

    function _convertBaseToAsset(address asset_, uint256 assets) internal view returns (uint256) {
        uint256 rate = provider.getRate(asset_);
        return assets.mulDiv(10 ** 18, rate, Math.Rounding.Floor);
    }

    function test_Vault_4626Invariants_depositBase(uint256 assets) public {
        if (assets < 100_000) return;
        if (assets > 100_000_000 ether) return;

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        deal(MC.WETH, address(this), 1 ether);
        IERC20(MC.WETH).approve(address(vault), 1 ether);
        IERC20(MC.WETH).transfer(address(vault), 1 ether);

        uint256 previewedShares = vault.previewDeposit(assets);
        assertApproxEqAbs(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqAbs(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        // Test the depositAsset function
        deal(MC.WETH, address(this), assets);
        IERC20(MC.WETH).approve(address(vault), assets);

        address receiver = address(this);
        uint256 depositedShares = vault.deposit(assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_depositAsset(uint256 assets) public {
        if (assets < 100_000) return;
        if (assets > 100_000_000 ether) return;

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertApproxEqAbs(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqAbs(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        // Test the depositAsset function
        deal(MC.WETH, address(this), assets);
        IERC20(MC.WETH).approve(address(vault), assets);

        address receiver = address(this);
        uint256 depositedShares = vault.depositAsset(assetAddress, assets, receiver);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_mint(uint256 shares) public {
        if (shares < 100_000) return;
        if (shares > 100_000 ether) return;

        address alice = address(10);
        vm.label(alice, "Alice");

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        uint256 totalAssets = vault.totalAssets();
        assertGt(totalAssets, 0, "Total assets should be greater than 0");

        // Test the convertToAssets function
        uint256 assets = vault.convertToAssets(shares);
        assertGt(assets, 0, "Assets should be greater than 0");

        deal(alice, assets);

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqAbs(previewedAssets, assets, 3, "Previewed assets should equal the converted assets");

        // Test the mint function
        vm.startPrank(alice);
        (bool success,) = MC.WETH.call{value: assets}("");
        assertTrue(success, "Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        uint256 mintedAssets = vault.mint(shares, alice);
        assertEq(mintedAssets, assets, "Minted assets should equal the converted assets");
        vm.stopPrank();

        ProcessorUtils.allocateToBuffer(vault, assets, PROCESSOR);

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_redeem(uint256 assets) public {
        if (assets < 100_000_000) return;
        if (assets > 100_000 ether) return;

        address baseAsset = vault.asset();
        deal(baseAsset, user, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        vm.startPrank(user);
        IERC20(baseAsset).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(baseAsset, assets, user);
        vm.stopPrank();

        assertApproxEqAbs(depositedShares, shares, 3, "Deposited shares should equal the converted shares");

        // hypothetically allocated 100% to the buffer
        ProcessorUtils.allocateToBuffer(vault, assets, PROCESSOR);
        vault.processAccounting();

        // Test the previewRedeem function
        uint256 previewedRedeemAssets = vault.previewRedeem(depositedShares);
        convertedAssets = vault.convertToAssets(depositedShares);

        assertApproxEqAbs(
            previewedRedeemAssets,
            convertedAssets - vault._feeOnTotal(convertedAssets, user),
            3,
            "Previewed redeem assets should equal the original assets with withdrawal fee applied"
        );

        uint256 redeemableShares = vault.maxRedeem(user);
        uint256 redeemedAssets;
        {
            assertEq(redeemableShares, depositedShares, "Redeemable shares should equal the original shares");

            uint256 initialBalance = IERC20(baseAsset).balanceOf(user);

            convertedAssets = vault.convertToAssets(redeemableShares);
            redeemedAssets = vault.previewRedeem(redeemableShares);
            uint256 withdrawalFee = redeemedAssets * vault.baseWithdrawalFee() / FeeMath.BASIS_POINT_SCALE;

            vm.startPrank(user);
            uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
            vault.redeem(redeemableShares, user, user);
            assertGt(vault.convertToAssets(10 ** vault.decimals()), exchangeRateBefore, "exchangeRate not as expected");
            vm.stopPrank();

            assertEq(redeemedAssets, previewedRedeemAssets, "Redeemed assets should equal the preview");
            assertApproxEqAbs(
                redeemedAssets,
                convertedAssets - withdrawalFee,
                3,
                "Redeemed assets should equal the original assets minus withdrawal fee"
            );
            assertEq(
                IERC20(baseAsset).balanceOf(user),
                initialBalance + redeemedAssets,
                "Final balance should reflect the redeemed assets"
            );
        }

        uint256 performanceFeeSharesMinted;
        {
            uint256 totalSupplyBefore = vault.totalSupply();
            uint256 totalAssetsBefore = vault.totalAssets();
            vault.processAccounting();
            uint256 totalSupplyAfter = vault.totalSupply();
            uint256 totalAssetsAfter = vault.totalAssets();
            performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
            if (performanceFeeSharesMinted > 0) {
                assertApproxEqAbs(
                    vault.convertToAssets(performanceFeeSharesMinted),
                    (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee() / 1e18,
                    1e12,
                    "performance fee shares should be equal to performance fee amount"
                );
            }
        }
        totalSupplyInvariant(initialSupply + depositedShares - redeemableShares + performanceFeeSharesMinted);
        totalAssetsInvariant(initialAssets + assets - redeemedAssets);
    }

    function test_Vault_4626Invariants_withdraw(uint256 assets) public {
        if (assets < 100_000_000) return;
        if (assets > 100_000_000 ether) return;

        deal(MC.WETH, user, assets);

        uint256 shares = vault.convertToShares(assets);
        assertGe(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        address baseAsset = vault.asset();
        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();
        vm.startPrank(user);
        IERC20(baseAsset).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(baseAsset, assets, user);
        assertApproxEqAbs(depositedShares, shares, 3, "Deposited shares should equal the converted shares");
        vm.stopPrank();

        vault.processAccounting();

        // hypothetically allocated 100% to the buffer
        ProcessorUtils.allocateToBuffer(vault, IERC20(baseAsset).balanceOf(address(vault)), PROCESSOR);

        uint256 sharesWithFee = vault.convertToShares(assets + vault._feeOnRaw(assets, user));

        // Test the previewWithdraw function
        uint256 previewedWithdrawShares = vault.previewWithdraw(assets);
        assertApproxEqAbs(
            previewedWithdrawShares, sharesWithFee, 3, "Previewed withdraw shares should equal the original shares"
        );

        vm.startPrank(user);
        uint256 withdrawableAssets;
        {
            convertedAssets = vault.convertToAssets(depositedShares);
            withdrawableAssets = vault.maxWithdraw(user);
            uint256 withdrawalFee = vault._feeOnTotal(convertedAssets, user);
            assertApproxEqAbs(
                withdrawableAssets * vault.baseWithdrawalFee() / FeeMath.BASIS_POINT_SCALE,
                withdrawalFee,
                3,
                "withdrawalFee should be correct"
            );
            assertApproxEqAbs(
                withdrawableAssets,
                convertedAssets - withdrawalFee,
                3,
                "Withdrawable assets should equal the original assets"
            );
        }

        uint256 withdrawnShares;
        {
            uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
            withdrawnShares = vault.withdraw(withdrawableAssets, user, user);
            uint256 exchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());
            assertGt(exchangeRateAfter, exchangeRateBefore, "exchangeRate not as expected");
            assertApproxEqAbs(withdrawnShares, depositedShares, 3, "Withdrawn shares should equal previous shares");
            vm.stopPrank();
        }

        uint256 performanceFeeSharesMinted;
        {
            uint256 totalSupplyBefore = vault.totalSupply();
            uint256 totalAssetsBefore = vault.totalAssets();
            vault.processAccounting();
            uint256 totalSupplyAfter = vault.totalSupply();
            uint256 totalAssetsAfter = vault.totalAssets();
            performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
            if (performanceFeeSharesMinted > 0) {
                assertApproxEqAbs(
                    vault.convertToAssets(performanceFeeSharesMinted),
                    (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee() / 1e18,
                    1e12,
                    "performance fee shares should be equal to performance fee amount"
                );
            }
        }
        totalSupplyInvariant(initialSupply + depositedShares - withdrawnShares + performanceFeeSharesMinted);
        totalAssetsInvariant(initialAssets + assets - withdrawableAssets);

        uint256 finalBalance = IERC20(baseAsset).balanceOf(user);
        assertApproxEqAbs(finalBalance, withdrawableAssets, 3, "Final balance should reflect the withdrawn assets");
    }

    function _setSTETHActive() internal {
        vm.startPrank(ADMIN);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vm.stopPrank();

        uint256 index = vault.getAsset(MC.STETH).index;
        IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
        vault.updateAsset(index, fields);
    }

    function test_Vault_4626Invariants_depositStETHWithReferral(uint256 assets) public {
        if (assets < 100_000) return;
        if (assets > 1_000 ether) return;

        _setSTETHActive();

        address alice = address(10);

        address receiver = address(125126126);

        address referrer = address(1222222);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(new XReferralAdapter()), MC.PROXY_ADMIN, "");
        XReferralAdapter adapter = XReferralAdapter(address(proxy));

        {
            // Deal WETH to alice and convert to stETH
            deal(alice, assets);
            vm.startPrank(alice);
            (bool success,) = MC.STETH.call{value: assets}("");
            assertTrue(success, "stETH deposit failed");
            vm.stopPrank();

            vm.startPrank(alice);
        }

        // Test the convertToShares function for stETH
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        assertApproxEqAbs(vault.convertToAssets(shares), assets, 3, "Converted assets should equal the original assets");

        // Get vault's stETH balance before deposit
        uint256 vaultStETHBalanceBefore = IERC20(MC.STETH).balanceOf(address(vault));

        // Approve adapter to spend stETH
        IERC20(MC.STETH).approve(address(adapter), assets);

        {
            uint256 depShares = adapter.depositAssetWithReferral(address(vault), MC.STETH, assets, referrer, receiver);
            assertApproxEqAbs(depShares, shares, 3, "Deposited shares should equal the converted shares");
        }

        vm.stopPrank();

        // Verify final balances
        uint256 vaultStETHBalanceAfter = IERC20(MC.STETH).balanceOf(address(vault));
        assertApproxEqAbs(
            vaultStETHBalanceAfter - vaultStETHBalanceBefore,
            assets,
            3,
            "Vault stETH balance should increase by the deposited amount"
        );

        uint256 userShares = vault.balanceOf(receiver);
        assertApproxEqAbs(userShares, shares, 3, "Receiver should have received correct shares");
        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function _process(address target, uint256 value, bytes memory data) internal returns (bytes memory returnData) {
        address[] memory targets = new address[](1);
        targets[0] = target;

        uint256[] memory values = new uint256[](1);
        values[0] = value;

        bytes[] memory datas = new bytes[](1);
        datas[0] = data;

        vm.prank(PROCESSOR);
        bytes[] memory returnDatas = vault.processor(targets, values, datas);
        returnData = returnDatas[0];
    }

    function _processApprove(address token, address spender, uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, amount);
        _process(token, 0, data);
    }

    function _processDeposit(address erc4626, uint256 amount) internal returns (uint256 shares) {
        bytes memory data = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));
        bytes memory returnData = _process(erc4626, 0, data);
        (shares) = abi.decode(returnData, (uint256));
    }

    function _processDepositAsset(address erc4626, address asset, uint256 amount) internal returns (uint256 shares) {
        bytes memory data =
            abi.encodeWithSignature("depositAsset(address,uint256,address)", asset, amount, address(vault));
        bytes memory returnData = _process(erc4626, 0, data);
        (shares) = abi.decode(returnData, (uint256));
    }

    function _processWithdraw(address erc4626, uint256 amount) internal returns (uint256 shares) {
        bytes memory data =
            abi.encodeWithSignature("withdraw(uint256,address,address)", amount, address(vault), address(vault));
        bytes memory returnData = _process(erc4626, 0, data);
        (shares) = abi.decode(returnData, (uint256));
    }

    function _processWithdrawAsset(address erc4626, address asset, uint256 amount) internal returns (uint256 shares) {
        bytes memory data = abi.encodeWithSignature(
            "withdrawAsset(address,uint256,address,address)", asset, amount, address(vault), address(vault)
        );
        bytes memory returnData = _process(erc4626, 0, data);
        (shares) = abi.decode(returnData, (uint256));
    }

    function _processRedeem(address erc4626, uint256 amount) internal returns (uint256 assets) {
        bytes memory data =
            abi.encodeWithSignature("redeem(uint256,address,address)", amount, address(vault), address(vault));
        bytes memory returnData = _process(erc4626, 0, data);
        (assets) = abi.decode(returnData, (uint256));
    }

    function _processDepositWETH(uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("deposit()");
        _process(MC.WETH, amount, data);
    }

    function _processWithdrawWETH(uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("withdraw(uint256)", amount);
        _process(MC.WETH, 0, data);
    }

    function _processSubmitETH(uint256 amount) internal returns (uint256 amountSTETH) {
        bytes memory data = abi.encodeWithSignature("submit(address)", address(vault));
        bytes memory returnData = _process(MC.STETH, amount, data);
        (amountSTETH) = abi.decode(returnData, (uint256));
    }

    function _processWrapSTETH(uint256 amount) internal returns (uint256 amountWSTETH) {
        bytes memory data = abi.encodeWithSignature("wrap(uint256)", amount);
        bytes memory returnData = _process(MC.WSTETH, 0, data);
        (amountWSTETH) = abi.decode(returnData, (uint256));
    }

    function _processUnwrapWSTETH(uint256 amount) internal returns (uint256 amountSTETH) {
        bytes memory data = abi.encodeWithSignature("unwrap(uint256)", amount);
        bytes memory returnData = _process(MC.WSTETH, 0, data);
        (amountSTETH) = abi.decode(returnData, (uint256));
    }

    function _processYnETHDepositETH(uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("depositETH(address)", address(vault));
        _process(MC.YNETH, amount, data);
    }

    function _processYnEigenDeposit(address erc4626, address asset, uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("deposit(address,uint256,address)", asset, amount, address(vault));
        _process(erc4626, 0, data);
    }

    function _processMintOETH(uint256 amount) internal {
        bytes memory data = abi.encodeWithSignature("mint(address,uint256,uint256)", MC.WETH, amount, amount);
        _process(MC.OETH_VAULT, 0, data);
    }

    function test_Vault_4626Invariants_Smokehouse_WSTETH(uint256 amount) public {
        if (amount < 0.01 ether) return;
        if (amount > 100_000 ether) return;

        {
            // deposit some WETH into the vault
            address alice = address(10);
            deal(MC.WETH, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), amount);
            vault.deposit(amount, alice);
            vm.stopPrank();
        }

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();
        uint256 totalSupplyBefore;
        uint256 totalSupplyAfter;
        uint256 performanceFeeShares;
        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);
            totalSupplyBefore = vault.totalSupply();
            uint256 totalAssetsBefore = vault.totalAssets();
            vault.processAccounting();
            totalSupplyAfter = vault.totalSupply();
            uint256 totalAssetsAfter = vault.totalAssets();
            performanceFeeShares = totalSupplyAfter - totalSupplyBefore;
            if (performanceFeeShares > 0) {
                assertApproxEqAbs(
                    vault.convertToAssets(performanceFeeShares),
                    (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee() / 1e18,
                    1e12,
                    "performance fee shares should be equal to performance fee amount"
                );
            }
            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        uint256 amountWSTETH;
        {
            // convert ETH to wstETH
            uint256 initialWSTETH = IERC20(MC.WSTETH).balanceOf(address(vault));

            uint256 amountSTETH = _processSubmitETH(amount);
            _processApprove(MC.STETH, MC.WSTETH, amountSTETH);
            amountWSTETH = _processWrapSTETH(amountSTETH);
            totalSupplyBefore = vault.totalSupply();
            uint256 totalAssetsBefore = vault.totalAssets();
            vault.processAccounting();
            totalSupplyAfter = vault.totalSupply();
            uint256 totalAssetsAfter = vault.totalAssets();
            performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
            uint256 sharesMinted = totalSupplyAfter - totalSupplyBefore;
            if (sharesMinted > 0) {
                assertApproxEqAbs(
                    vault.convertToAssets(sharesMinted),
                    (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee() / 1e18,
                    1e12,
                    "performance fee shares should be equal to performance fee amount"
                );
            }
            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialWSTETH + amountWSTETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        uint256 amountSmokehouseWSTETH;
        {
            // deposit wstETH into smokehouse
            uint256 initialSmokehouseWSTETH = IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault));

            _processApprove(MC.WSTETH, MC.SMOKEHOUSE_WSTETH, amountWSTETH);
            amountSmokehouseWSTETH = _processDeposit(MC.SMOKEHOUSE_WSTETH, amountWSTETH);
            totalSupplyBefore = vault.totalSupply();
            vault.processAccounting();
            totalSupplyAfter = vault.totalSupply();
            performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
            assertApproxEqAbs(
                IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault)),
                initialSmokehouseWSTETH + amountSmokehouseWSTETH,
                3,
                "vault should have received smokehouse wstETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        uint256 receivedWSTETH;
        {
            // redeem smokehouse wstETH for wstETH
            uint256 initialReceivedWSTETH = IERC20(MC.WSTETH).balanceOf(address(vault));

            receivedWSTETH = _processRedeem(MC.SMOKEHOUSE_WSTETH, amountSmokehouseWSTETH);
            totalSupplyBefore = vault.totalSupply();
            vault.processAccounting();
            totalSupplyAfter = vault.totalSupply();
            performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialReceivedWSTETH + receivedWSTETH,
                "vault should have received stETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        {
            // deposit wstETH into smokehouse
            uint256 initialSmokehouseWSTETH = IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault));

            _processApprove(MC.WSTETH, MC.SMOKEHOUSE_WSTETH, receivedWSTETH);
            amountSmokehouseWSTETH = _processDeposit(MC.SMOKEHOUSE_WSTETH, receivedWSTETH);
            totalSupplyBefore = vault.totalSupply();
            vault.processAccounting();
            totalSupplyAfter = vault.totalSupply();
            performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
            assertApproxEqAbs(
                IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault)),
                initialSmokehouseWSTETH + amountSmokehouseWSTETH,
                3,
                "vault should have received smokehouse wstETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        {
            uint256 maxWithdraw = IERC4626(MC.SMOKEHOUSE_WSTETH).maxWithdraw(address(vault));
            _processWithdraw(MC.SMOKEHOUSE_WSTETH, maxWithdraw);
            totalSupplyBefore = vault.totalSupply();
            vault.processAccounting();
            totalSupplyAfter = vault.totalSupply();
            performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_WETH_Donation(uint256 amount, bool processAfterWithdraw) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            dealMore(address(vault), amount);

            // convert ETH to WETH
            _processDepositWETH(amount);
            uint256 performanceFee = IFeeHooks(address(vault.hooks())).performanceFee();
            uint256 performanceFeeAmount = (amount * performanceFee) / 1e18;
            uint256 vaultBalanceOfFeeRecipientBefore =
                vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
            // process accounting to update for the donation
            vault.processAccounting();
            uint256 vaultBalanceOfFeeRecipientAfter =
                vault.balanceOf(IFeeHooks(address(vault.hooks())).performanceFeeRecipient());
            uint256 performanceFeeShares = vaultBalanceOfFeeRecipientAfter - vaultBalanceOfFeeRecipientBefore;

            assertApproxEqAbs(
                vault.convertToAssets(performanceFeeShares),
                performanceFeeAmount,
                1e12,
                "performance fee shares should be equal to performance fee amount"
            );

            assertEqThreshold(
                vault.totalSupply(),
                initialSupply + performanceFeeShares,
                5000,
                "totalSupply should be equal to initialSupply plus performanceFeeShares"
            );
            totalAssetsInvariant(initialAssets + amount);
        }

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);
            uint256 performanceFeeSharesMinted;
            if (processAfterWithdraw) {
                uint256 totalSupplyBefore = vault.totalSupply();
                uint256 totalAssetsBefore = vault.totalAssets();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                uint256 totalAssetsAfter = vault.totalAssets();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                if (performanceFeeSharesMinted > 0) {
                    assertApproxEqAbs(
                        vault.convertToAssets(performanceFeeSharesMinted),
                        (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee()
                            / 1e18,
                        1e12,
                        "performance fee shares should be equal to performance fee amount"
                    );
                }
            }

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_WETH_Deposit(uint256 amount, bool processAfterDeposit, bool processAfterWithdraw)
        public
    {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            address alice = address(10);
            deal(alice, amount);

            vm.startPrank(alice);
            (bool success,) = MC.WETH.call{value: amount}("");
            assertTrue(success, "WETH deposit failed");
            IERC20(MC.WETH).approve(address(vault), amount);
            uint256 depositeShares = vault.deposit(amount, alice);
            vm.stopPrank();

            if (processAfterDeposit) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply + depositeShares);
            totalAssetsInvariant(initialAssets + amount);
        }

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);

            if (processAfterWithdraw) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            uint256 finalVaultTotalAssets = vault.totalAssets();
            assertApproxEqAbs(
                initialAssets,
                finalVaultTotalAssets,
                3,
                "Vault totalAssets should be original totalAssets plus additional"
            );
        }
    }

    function test_Vault_4626Invariants_Buffer(uint256 amount, bool processAfterWETH, bool processAfterBuffer) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        deal(address(vault), amount);

        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            // convert ETH to WETH
            _processDepositWETH(amount);

            if (processAfterWETH) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        {
            // deposit WETH into EULER_WETH_22_VAULT (buffer)
            _processApprove(MC.WETH, MC.EULER_WETH_22_VAULT, amount);
            _processDeposit(MC.EULER_WETH_22_VAULT, amount);

            if (processAfterBuffer) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_YNETH(uint256 amount, bool process) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        deal(address(vault), amount);

        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            // convert ETH to YNETH
            _processYnETHDepositETH(amount);

            if (process) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_YNLSDE_WSTETH(
        uint256 amount,
        bool processAfterWETH,
        bool processAfterWSTETH,
        bool processAfterYnLSDE
    ) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        {
            // deposit some WETH into the vault
            address alice = address(10);
            deal(MC.WETH, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), amount);
            vault.deposit(amount, alice);
            vm.stopPrank();
        }

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);

            if (processAfterWETH) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        uint256 amountWSTETH;
        {
            // convert ETH to wstETH
            uint256 initialWSTETH = IERC20(MC.WSTETH).balanceOf(address(vault));

            uint256 amountSTETH = _processSubmitETH(amount);
            _processApprove(MC.STETH, MC.WSTETH, amountSTETH);
            amountWSTETH = _processWrapSTETH(amountSTETH);

            if (processAfterWSTETH) {
                vault.processAccounting();
            }

            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialWSTETH + amountWSTETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            // deposit WSETH into YNLSDE
            _processApprove(MC.WSTETH, MC.YNLSDE, amountWSTETH);
            _processYnEigenDeposit(MC.YNLSDE, MC.WSTETH, amountWSTETH);

            if (processAfterYnLSDE) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_YNLSDE_WOETH(uint256 amount, bool processAfterWOETH, bool processAfterYnLSDE)
        public
    {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        {
            // deposit some WETH into the vault
            address alice = address(10);
            deal(MC.WETH, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), amount);
            vault.deposit(amount, alice);
            vm.stopPrank();
        }

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 amountWOETH;
        {
            // convert ETH to woETH
            uint256 initialWOETH = IERC20(MC.WOETH).balanceOf(address(vault));

            _processApprove(MC.WETH, MC.OETH_VAULT, amount);
            _processMintOETH(amount);
            _processApprove(MC.OETH, MC.WOETH, amount);
            amountWOETH = _processDeposit(MC.WOETH, amount);

            uint256 performanceFeeSharesMinted;
            if (processAfterWOETH) {
                uint256 totalSupplyBefore = vault.totalSupply();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                assertLt(performanceFeeSharesMinted, 1e15, "performanceFeeSharesMinted should be less than 1e12");
            }

            assertEq(
                IERC20(MC.WOETH).balanceOf(address(vault)),
                initialWOETH + amountWOETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
            // changing by 1e12 since underlying asset rates are changing
            assertApproxEqRel(
                vault.totalAssets(), initialAssets, 1e12, "vault should have received woETH after deposit"
            );
        }

        {
            // deposit WOETH into YNLSDE
            _processApprove(MC.WOETH, MC.YNLSDE, amountWOETH);
            _processYnEigenDeposit(MC.YNLSDE, MC.WOETH, amountWOETH);
            initialSupply = vault.totalSupply();
            uint256 performanceFeeSharesMinted;
            if (processAfterYnLSDE) {
                uint256 totalSupplyBefore = vault.totalSupply();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                assertLt(performanceFeeSharesMinted, 1e15, "performanceFeeSharesMinted should be less than 1e12");
            }

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
            // changing by 1e12 since underlying asset rates are changing
            assertApproxEqRel(
                vault.totalAssets(), initialAssets, 1e12, "vault should have received ynLSDe after deposit"
            );
        }
    }

    function test_Vault_4626Invariants_WOETH(
        uint256 amount,
        bool processAfterFirstDeposit,
        bool processAfterRedeem,
        bool processAfterSecondDeposit,
        bool processAfterWithdraw
    ) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        {
            // deposit some WETH into the vault
            address alice = address(10);
            deal(MC.WETH, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), amount);
            vault.deposit(amount, alice);
            vm.stopPrank();
        }

        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 amountWOETH;
        {
            // convert ETH to woETH
            uint256 initialWOETH = IERC20(MC.WOETH).balanceOf(address(vault));

            _processApprove(MC.WETH, MC.OETH_VAULT, amount);
            _processMintOETH(amount);
            _processApprove(MC.OETH, MC.WOETH, amount);
            amountWOETH = _processDeposit(MC.WOETH, amount);

            uint256 performanceFeeSharesMinted;
            if (processAfterFirstDeposit) {
                uint256 totalSupplyBefore = vault.totalSupply();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                assertLt(performanceFeeSharesMinted, 1e15, "performanceFeeSharesMinted should be less than 1e12");
            }

            assertEq(
                IERC20(MC.WOETH).balanceOf(address(vault)),
                initialWOETH + amountWOETH,
                "vault should have received woETH"
            );

            // changing by 1e12 since underlying asset rates are changing
            assertApproxEqRel(
                vault.totalAssets(), initialAssets, 1e12, "vault should have received woETH after deposit"
            );

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
        }

        uint256 receivedOETH;
        initialSupply = vault.totalSupply();
        {
            // unwrap woETH
            receivedOETH = _processRedeem(MC.WOETH, amountWOETH);
            uint256 performanceFeeSharesMinted;
            if (processAfterRedeem) {
                uint256 totalSupplyBefore = vault.totalSupply();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                assertLt(performanceFeeSharesMinted, 1e15, "performanceFeeSharesMinted should be less than 1e12");
            }

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
            // changing by 1e12 since underlying asset rates are changing
            assertApproxEqRel(vault.totalAssets(), initialAssets, 1e12, "vault should have received oETH after redeem");
        }

        {
            uint256 initialWOETH = IERC20(MC.WOETH).balanceOf(address(vault));

            _processApprove(MC.OETH, MC.WOETH, receivedOETH);
            amountWOETH = _processDeposit(MC.WOETH, receivedOETH);

            uint256 performanceFeeSharesMinted;
            initialSupply = vault.totalSupply();
            if (processAfterSecondDeposit) {
                uint256 totalSupplyBefore = vault.totalSupply();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                assertLt(performanceFeeSharesMinted, 1e15, "performanceFeeSharesMinted should be less than 1e12");
            }

            assertEq(
                IERC20(MC.WOETH).balanceOf(address(vault)),
                initialWOETH + amountWOETH,
                "vault should have received woETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
            // changing by 1e12 since underlying asset rates are changing
            assertApproxEqRel(vault.totalAssets(), initialAssets, 1e12, "vault should have received woETH second time");
        }

        {
            uint256 maxWithdraw = IERC4626(MC.WOETH).maxWithdraw(address(vault));
            _processWithdraw(MC.WOETH, maxWithdraw);

            uint256 performanceFeeSharesMinted;
            uint256 totalSupplyBefore = vault.totalSupply();
            initialSupply = vault.totalSupply();
            if (processAfterWithdraw) {
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                performanceFeeSharesMinted = totalSupplyAfter - totalSupplyBefore;
                assertLt(performanceFeeSharesMinted, 1e15, "performanceFeeSharesMinted should be less than 1e12");
            }

            totalSupplyInvariant(initialSupply + performanceFeeSharesMinted);
            // changing by 1e12 since underlying asset rates are changing
            assertApproxEqRel(
                vault.totalAssets(), initialAssets, 1e12, "vault should have received oETH after withdraw"
            );
        }
    }

    function test_Vault_4626Invariants_Wrap_Unwrap_WSTETH(
        uint256 amount,
        bool processAfterWETH,
        bool processAfterWrap,
        bool processAfterUnwrap
    ) public {
        amount = bound(amount, 100000, 100_000 ether);

        {
            // deposit some WETH into the vault
            address alice = address(10);
            deal(MC.WETH, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), amount);
            vault.deposit(amount, alice);
            vm.stopPrank();
        }

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();
        uint256 performanceFeeShares = 0;

        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);

            if (processAfterWETH) {
                uint256 totalSupplyBefore = vault.totalSupply();
                uint256 totalAssetsBefore = vault.totalAssets();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                uint256 totalAssetsAfter = vault.totalAssets();
                performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
                uint256 sharesMinted = totalSupplyAfter - totalSupplyBefore;
                if (sharesMinted > 0) {
                    assertApproxEqAbs(
                        vault.convertToAssets(sharesMinted),
                        (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee()
                            / 1e18,
                        1e12,
                        "performance fee shares should be equal to performance fee amount"
                    );
                }
            }

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        uint256 amountWSTETH;
        {
            // convert ETH to wstETH
            uint256 initialWSTETH = IERC20(MC.WSTETH).balanceOf(address(vault));

            uint256 amountSTETH = _processSubmitETH(amount);
            _processApprove(MC.STETH, MC.WSTETH, amountSTETH);
            amountWSTETH = _processWrapSTETH(amountSTETH);

            if (processAfterWrap) {
                uint256 totalSupplyBefore = vault.totalSupply();
                uint256 totalAssetsBefore = vault.totalAssets();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                uint256 totalAssetsAfter = vault.totalAssets();
                performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
                uint256 sharesMinted = totalSupplyAfter - totalSupplyBefore;
                if (sharesMinted > 0) {
                    assertApproxEqAbs(
                        vault.convertToAssets(sharesMinted),
                        (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee()
                            / 1e18,
                        1e12,
                        "performance fee shares should be equal to performance fee amount"
                    );
                }
            }

            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialWSTETH + amountWSTETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }

        {
            // unwrap wstETH
            _processUnwrapWSTETH(amountWSTETH);

            if (processAfterUnwrap) {
                uint256 totalSupplyBefore = vault.totalSupply();
                uint256 totalAssetsBefore = vault.totalAssets();
                vault.processAccounting();
                uint256 totalSupplyAfter = vault.totalSupply();
                uint256 totalAssetsAfter = vault.totalAssets();
                performanceFeeShares += totalSupplyAfter - totalSupplyBefore;
                uint256 sharesMinted = totalSupplyAfter - totalSupplyBefore;
                if (sharesMinted > 0) {
                    assertApproxEqAbs(
                        vault.convertToAssets(sharesMinted),
                        (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee()
                            / 1e18,
                        1e12,
                        "performance fee shares should be equal to performance fee amount"
                    );
                }
            }

            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_Withdrawer_Deposit(uint256 amount, uint8 i, bool process) public {
        vm.assume(amount > 1e8);
        vm.assume(amount < 1e5 ether);

        uint256 assetcount = 7;
        vm.assume(i < assetcount);

        withdrawer.processAccounting();
        vault.processAccounting();

        address alice = address(0xa11ce);

        address[] memory assets = new address[](7);
        uint256 index = 0;

        assets[index++] = MC.WETH;
        assets[index++] = MC.STETH;
        assets[index++] = MC.WSTETH;
        assets[index++] = MC.WOETH;
        assets[index++] = MC.OETH;
        assets[index++] = MC.YNLSDE;
        assets[index++] = MC.YNETH;

        dealAsset(assets[i], alice, amount);

        // dealt asset is not equal to shares obtained for stETH, ynETH, ynLSDe
        uint256 donatedAmount = IERC20(assets[i]).balanceOf(alice);

        vm.startPrank(alice);
        IERC20(assets[i]).transfer(address(vault), donatedAmount);
        vm.stopPrank();

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        _processApprove(assets[i], address(withdrawer), donatedAmount);
        _processDepositAsset(address(withdrawer), assets[i], donatedAmount);

        if (process) {
            withdrawer.processAccounting();
            vault.processAccounting();
        }

        assertApproxEqRel(vault.totalSupply(), initialSupply, 1e15, "totalSupply should be near the same as before");
        assertApproxEqRel(vault.totalAssets(), initialAssets, 1e15, "totalAssets should be near the same as before");
    }

    function test_Vault_4626Invariants_Withdrawer_Withdraw(
        uint256 amount,
        bool processAfterDeposit,
        bool processAfterWithdraw,
        bool processAfterSecondDeposit,
        bool processAfterWithdrawAsset
    ) public {
        vm.assume(amount > 1 ether);
        vm.assume(amount < 100_000 ether);

        // Total assets increase slightly after withdrawing from withdrawer
        uint256 MAX_FEE_SHARES = 1e4;

        withdrawer.processAccounting();
        vault.processAccounting();

        {
            // deposit some WETH into the vault
            address alice = address(10);
            deal(MC.WETH, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.WETH).approve(address(vault), amount);
            vault.deposit(amount, alice);
            vm.stopPrank();
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            _processApprove(MC.WETH, address(withdrawer), amount);
            _processDepositAsset(address(withdrawer), MC.WETH, amount);

            if (processAfterDeposit) {
                withdrawer.processAccounting();
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            _processWithdraw(address(withdrawer), amount);

            uint256 performanceFeeShares = 0;
            if (processAfterWithdraw) {
                withdrawer.processAccounting();

                uint256 totalSupplyBefore = vault.totalSupply();
                vault.processAccounting();

                performanceFeeShares = vault.totalSupply() - totalSupplyBefore;
            }

            assertLe(performanceFeeShares, MAX_FEE_SHARES, "performanceFeeShares should be less than 10");
            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
            initialSupply = vault.totalSupply();
        }

        {
            _processApprove(MC.WETH, address(withdrawer), amount);
            _processDepositAsset(address(withdrawer), MC.WETH, amount);

            uint256 performanceFeeShares = 0;
            if (processAfterSecondDeposit) {
                uint256 totalSupplyBefore = vault.totalSupply();
                withdrawer.processAccounting();
                vault.processAccounting();
                performanceFeeShares = vault.totalSupply() - totalSupplyBefore;
            }

            assertLe(performanceFeeShares, MAX_FEE_SHARES, "performanceFeeShares should be less than 10");
            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
            initialSupply = vault.totalSupply();
        }

        {
            _processWithdraw(address(withdrawer), amount);

            uint256 performanceFeeShares = 0;
            if (processAfterWithdrawAsset) {
                uint256 totalSupplyBefore = vault.totalSupply();
                withdrawer.processAccounting();
                vault.processAccounting();
                performanceFeeShares = vault.totalSupply() - totalSupplyBefore;
            }

            assertLe(performanceFeeShares, MAX_FEE_SHARES, "performanceFeeShares should be less than 10");
            totalSupplyInvariant(initialSupply + performanceFeeShares);
            totalAssetsInvariant(initialAssets);
        }
    }

    function testProcessAccountingBetweenOperations(
        uint256 amount,
        bool processAfterDeposit,
        bool processAfterWithdraw,
        bool processAfterAllocate
    ) public {
        vm.assume(amount > 0.1 ether && amount < 100 ether);

        address alice = address(10);
        vm.label(alice, "Alice");

        {
            deal(alice, 100000 ether);

            vm.startPrank(alice);
            (bool success,) = MC.WETH.call{value: 100000 ether}("");
            assertTrue(success, "WETH deposit failed");
            vm.stopPrank();
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 initialDepositedAmount = amount * 2;

        // Initial setup
        vm.startPrank(alice);
        IERC20(MC.WETH).approve(address(vault), initialDepositedAmount);
        uint256 depositedShares = vault.deposit(initialDepositedAmount, alice);
        vm.stopPrank();

        // Send WETH to buffer
        _processApprove(MC.WETH, address(vault.buffer()), amount);
        _processDeposit(address(vault.buffer()), amount);

        if (processAfterDeposit) {
            withdrawer.processAccounting();
            vault.processAccounting();
        }

        totalSupplyInvariant(initialSupply + depositedShares);
        totalAssetsInvariant(initialAssets + initialDepositedAmount);

        // Allocate to ynETH
        _processWithdrawWETH(amount);
        _processYnETHDepositETH(amount);

        if (processAfterAllocate) {
            withdrawer.processAccounting();
            vault.processAccounting();
        }

        totalSupplyInvariant(initialSupply + depositedShares);
        totalAssetsInvariant(initialAssets + initialDepositedAmount);

        uint256 withdrawableAssets = vault.maxWithdraw(alice);
        uint256 burnedShares;

        {
            vm.startPrank(alice);
            uint256 exchangeRateBefore = vault.convertToAssets(10 ** vault.decimals());
            burnedShares = vault.withdraw(withdrawableAssets, alice, alice);
            uint256 exchangeRateAfter = vault.convertToAssets(10 ** vault.decimals());
            assertGt(exchangeRateAfter, exchangeRateBefore, "exchangeRate not as expected");
            vm.stopPrank();
        }

        uint256 performanceFeeShares;
        if (processAfterWithdraw) {
            withdrawer.processAccounting();
            uint256 totalSupplyBefore = vault.totalSupply();
            uint256 totalAssetsBefore = vault.totalAssets();
            vault.processAccounting();
            uint256 totalSupplyAfter = vault.totalSupply();
            uint256 totalAssetsAfter = vault.totalAssets();
            performanceFeeShares = totalSupplyAfter - totalSupplyBefore;
            if (performanceFeeShares > 0) {
                assertApproxEqAbs(
                    vault.convertToAssets(performanceFeeShares),
                    (totalAssetsAfter - totalAssetsBefore) * IFeeHooks(address(vault.hooks())).performanceFee() / 1e18,
                    1e12,
                    "performance fee shares should be equal to performance fee amount"
                );
            }
        }
        totalSupplyInvariant(initialSupply + depositedShares - burnedShares + performanceFeeShares);
        totalAssetsInvariant(initialAssets + initialDepositedAmount - withdrawableAssets);
    }
}

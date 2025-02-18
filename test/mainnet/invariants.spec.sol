// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20, TransparentUpgradeableProxy, IERC4626} from "src/Common.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";

contract VaultMainnetInvariantsTest is Test, MainnetActors {
    Vault public vault;
    Withdrawer public withdrawer;

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade();
        vault = Vault(payable(MC.YNETHX));

        withdrawer = VaultVerification.getWithdrawer(vault);
        assertEq(vault.asset(), MC.WETH, "base asset should be weth");
    }

    function totalSupplyInvariant(uint256 supply) public view {
        uint256 finalVaultTotalSupply = vault.totalSupply();
        assertApproxEqRel(
            supply, finalVaultTotalSupply, 3, "Vault totalSupply should be original totalSupply plus additional"
        );
    }

    function totalAssetsInvariant(uint256 assets) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertApproxEqRel(
            assets, finalVaultTotalAssets, 1e14, "Vault totalAssets should be original totalAssets plus additional"
        );
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = vault.buffer();

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);

        vault.processAccounting();
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
        assertApproxEqRel(convertedAssets, assets, 1e14, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        deal(MC.WETH, address(this), 1 ether);
        IERC20(MC.WETH).approve(address(vault), 1 ether);
        IERC20(MC.WETH).transfer(address(vault), 1 ether);

        uint256 previewedShares = vault.previewDeposit(assets);
        assertApproxEqRel(previewedShares, shares, 1e14, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqRel(previewedAssets, assets, 1e14, "Previewed assets should equal the original assets");

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
        assertApproxEqRel(convertedAssets, assets, 1e14, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        uint256 previewedShares = vault.previewDeposit(assets);
        assertApproxEqRel(previewedShares, shares, 1e14, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqRel(previewedAssets, assets, 1e14, "Previewed assets should equal the original assets");

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
        if (shares > 100_000_000 ether) return;

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
        assertApproxEqRel(previewedAssets, assets, 1e14, "Previewed assets should equal the converted assets");

        // Test the mint function
        vm.startPrank(alice);
        (bool success,) = MC.WETH.call{value: assets}("");
        assertTrue(success, "Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), assets);

        uint256 mintedAssets = vault.mint(shares, alice);
        assertEq(mintedAssets, assets, "Minted assets should equal the converted assets");
        vm.stopPrank();

        allocateToBuffer(assets);

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_redeem(uint256 assets) public {
        if (assets < 100_000) return;
        if (assets > 100_000_000 ether) return;

        address alice = address(420);
        address baseAsset = vault.asset();
        deal(baseAsset, alice, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqRel(convertedAssets, assets, 1e14, "Converted assets should equal the original assets");

        vm.startPrank(alice);
        IERC20(baseAsset).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(baseAsset, assets, alice);
        vm.stopPrank();

        assertApproxEqRel(depositedShares, shares, 1e14, "Deposited shares should equal the converted shares");

        // hypothetically allocated 100% to the buffer
        allocateToBuffer(assets);

        // Test the previewRedeem function
        uint256 previewedRedeemAssets = vault.previewRedeem(shares);
        assertApproxEqRel(
            previewedRedeemAssets, assets, 2e15, "Previewed redeem assets should equal the original assets"
        );

        uint256 redeemableShares = vault.maxRedeem(alice);
        assertApproxEqRel(redeemableShares, shares, 1e15, "Redeemable shares should equal the original shares");

        uint256 initialBalance = IERC20(baseAsset).balanceOf(alice);

        vm.startPrank(alice);
        uint256 redeemedAssets = vault.redeem(redeemableShares, alice, alice);
        vm.stopPrank();

        vault.processAccounting();

        assertApproxEqRel(redeemedAssets, assets, 2e15, "Redeemed assets should equal the original assets");
        assertEq(
            IERC20(baseAsset).balanceOf(alice),
            initialBalance + redeemedAssets,
            "Final balance should reflect the redeemed assets"
        );

        totalSupplyInvariant(initialSupply + depositedShares - redeemableShares);
        totalAssetsInvariant(initialAssets + assets - redeemedAssets);
    }

    function test_Vault_4626Invariants_withdraw(uint256 assets) public {
        if (assets < 100_000) return;
        if (assets > 100_000_000 ether) return;

        address alice = address(10);
        deal(alice, assets);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        uint256 shares = vault.convertToShares(assets);
        assertGe(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqRel(convertedAssets, assets, 1e14, "Converted assets should equal the original assets");

        address baseAsset = vault.asset();

        vm.startPrank(alice);
        (bool success,) = MC.WETH.call{value: assets}("");
        assertTrue(success, "Weth deposit failed");
        IERC20(baseAsset).approve(address(vault), assets);
        uint256 depositedShares = vault.depositAsset(baseAsset, assets, alice);
        assertApproxEqRel(depositedShares, shares, 1e14, "Deposited shares should equal the converted shares");
        vm.stopPrank();

        vault.processAccounting();

        // hypothetically allocated 100% to the buffer
        allocateToBuffer(IERC20(baseAsset).balanceOf(address(vault)));

        // Test the previewWithdraw function
        uint256 previewedWithdrawShares = vault.previewWithdraw(assets);
        assertApproxEqRel(
            previewedWithdrawShares, shares, 2e15, "Previewed withdraw shares should equal the original shares"
        );

        vm.startPrank(alice);

        uint256 withdrawableAssets = vault.maxWithdraw(alice);
        assertApproxEqRel(withdrawableAssets, assets, 2e15, "Withdrawable assets should equal the original assets");

        uint256 withdrawnShares = vault.withdraw(withdrawableAssets, alice, alice);
        assertApproxEqRel(withdrawnShares, shares, 1e15, "Withdrawn shares should equal previous shares");
        vm.stopPrank();

        vault.processAccounting();

        uint256 finalBalance = IERC20(baseAsset).balanceOf(alice);
        assertApproxEqRel(finalBalance, assets, 2e15, "Final balance should reflect the withdrawn assets");

        totalSupplyInvariant(initialSupply + depositedShares - withdrawnShares);
        totalAssetsInvariant(initialAssets + assets - withdrawableAssets);
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

        // Deploy referral adapter
        address implementation = address(new XReferralAdapter());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, MC.PROXY_ADMIN, "");
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

        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqRel(convertedAssets, assets, 1e14, "Converted assets should equal the original assets");

        // Approve adapter to spend stETH
        IERC20(MC.STETH).approve(address(adapter), assets);

        uint256 depShares = adapter.depositAssetWithReferral(address(vault), MC.STETH, assets, referrer, receiver);
        assertApproxEqRel(depShares, shares, 1e14, "Deposited shares should equal the converted shares");

        vm.stopPrank();

        // Verify final balances
        uint256 vaultStETHBalance = IERC20(MC.STETH).balanceOf(address(vault));
        assertApproxEqRel(vaultStETHBalance, assets, 1e14, "Vault should have received stETH");

        uint256 userShares = vault.balanceOf(receiver);
        assertApproxEqRel(userShares, shares, 1e14, "Receiver should have received correct shares");
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

        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);

            vault.processAccounting();

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

            vault.processAccounting();

            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialWSTETH + amountWSTETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        uint256 amountSmokehouseWSTETH;
        {
            // deposit wstETH into smokehouse
            uint256 initialSmokehouseWSTETH = IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault));

            _processApprove(MC.WSTETH, MC.SMOKEHOUSE_WSTETH, amountWSTETH);
            amountSmokehouseWSTETH = _processDeposit(MC.SMOKEHOUSE_WSTETH, amountWSTETH);

            vault.processAccounting();

            assertApproxEqRel(
                IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault)),
                initialSmokehouseWSTETH + amountSmokehouseWSTETH,
                1e15,
                "vault should have received smokehouse wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        uint256 receivedWSTETH;
        {
            // redeem smokehouse wstETH for wstETH
            uint256 initialReceivedWSTETH = IERC20(MC.WSTETH).balanceOf(address(vault));

            receivedWSTETH = _processRedeem(MC.SMOKEHOUSE_WSTETH, amountSmokehouseWSTETH);

            vault.processAccounting();

            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialReceivedWSTETH + receivedWSTETH,
                "vault should have received stETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            // deposit wstETH into smokehouse
            uint256 initialSmokehouseWSTETH = IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault));

            _processApprove(MC.WSTETH, MC.SMOKEHOUSE_WSTETH, receivedWSTETH);
            amountSmokehouseWSTETH = _processDeposit(MC.SMOKEHOUSE_WSTETH, receivedWSTETH);

            vault.processAccounting();

            assertApproxEqRel(
                IERC20(MC.SMOKEHOUSE_WSTETH).balanceOf(address(vault)),
                initialSmokehouseWSTETH + amountSmokehouseWSTETH,
                1e15,
                "vault should have received smokehouse wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            uint256 maxWithdraw = IERC4626(MC.SMOKEHOUSE_WSTETH).maxWithdraw(address(vault));
            _processWithdraw(MC.SMOKEHOUSE_WSTETH, maxWithdraw);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_WETH(uint256 amount) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            deal(address(vault), amount);

            // convert ETH to WETH
            _processDepositWETH(amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets + amount);
        }

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        {
            // convert WETH to ETH
            _processWithdrawWETH(amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_Buffer(uint256 amount) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            deal(address(vault), amount);

            // convert ETH to WETH
            _processDepositWETH(amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets + amount);
        }

        initialAssets = vault.totalAssets();
        initialSupply = vault.totalSupply();

        {
            // deposit WETH into EULER_WETH_22_VAULT (buffer)
            _processApprove(MC.WETH, MC.EULER_WETH_22_VAULT, amount);
            _processDeposit(MC.EULER_WETH_22_VAULT, amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_YNETH(uint256 amount) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 ether);

        deal(address(vault), amount);

        vault.processAccounting();

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            // convert ETH to YNETH
            _processYnETHDepositETH(amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_YNLSDE_WSTETH(uint256 amount) public {
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

            vault.processAccounting();

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

            vault.processAccounting();

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

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_YNLSDE_WOETH(uint256 amount) public {
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

            vault.processAccounting();

            assertEq(
                IERC20(MC.WOETH).balanceOf(address(vault)),
                initialWOETH + amountWOETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            // deposit WOETH into YNLSDE
            _processApprove(MC.WOETH, MC.YNLSDE, amountWOETH);
            _processYnEigenDeposit(MC.YNLSDE, MC.WOETH, amountWOETH);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_WOETH(uint256 amount) public {
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

            vault.processAccounting();

            assertEq(
                IERC20(MC.WOETH).balanceOf(address(vault)),
                initialWOETH + amountWOETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        uint256 receivedOETH;
        {
            // unwrap woETH
            receivedOETH = _processRedeem(MC.WOETH, amountWOETH);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            uint256 initialWOETH = IERC20(MC.WOETH).balanceOf(address(vault));

            _processApprove(MC.OETH, MC.WOETH, receivedOETH);
            amountWOETH = _processDeposit(MC.WOETH, receivedOETH);

            vault.processAccounting();

            assertEq(
                IERC20(MC.WOETH).balanceOf(address(vault)),
                initialWOETH + amountWOETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            uint256 maxWithdraw = IERC4626(MC.WOETH).maxWithdraw(address(vault));
            _processWithdraw(MC.WOETH, maxWithdraw);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_Wrap_Unwrap_WSTETH(uint256 amount) public {
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

            vault.processAccounting();

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

            vault.processAccounting();

            assertEq(
                IERC20(MC.WSTETH).balanceOf(address(vault)),
                initialWSTETH + amountWSTETH,
                "vault should have received wstETH"
            );

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            // unwrap wstETH
            _processUnwrapWSTETH(amountWSTETH);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
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

    function test_Vault_4626Invariants_Withdrawer_Deposit(uint256 amount) public {
        vm.assume(amount > 10000);
        vm.assume(amount < 100_000 ether);

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

        for (uint256 i = 0; i < assets.length; i++) {
            dealAsset(assets[i], alice, amount);

            uint256 donatedAmount = IERC20(assets[i]).balanceOf(alice);
            assertApproxEqRel(donatedAmount, amount, 1e15, "Balance should match for asset");

            vm.startPrank(alice);
            IERC20(assets[i]).transfer(address(vault), donatedAmount);
            vm.stopPrank();

            vault.processAccounting();

            uint256 initialAssets = vault.totalAssets();
            uint256 initialSupply = vault.totalSupply();

            _processApprove(assets[i], address(withdrawer), donatedAmount);
            _processDepositAsset(address(withdrawer), assets[i], donatedAmount);

            withdrawer.processAccounting();
            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function test_Vault_4626Invariants_Withdrawer_Withdraw(uint256 amount) public {
        vm.assume(amount > 10000);
        vm.assume(amount < 100_000 ether);

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
            _processApprove(MC.WETH, address(withdrawer), amount);
            _processDepositAsset(address(withdrawer), MC.WETH, amount);

            withdrawer.processAccounting();
            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            _processWithdraw(address(withdrawer), amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            _processApprove(MC.WETH, address(withdrawer), amount);
            _processDepositAsset(address(withdrawer), MC.WETH, amount);

            withdrawer.processAccounting();
            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }

        {
            _processWithdrawAsset(address(withdrawer), MC.WETH, amount);

            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets);
        }
    }

    function testProcessAccountingBetweenOperations(
        uint256 amount,
        bool processAfterDeposit
        // bool processAfterWithdraw,
        // bool processAfterAllocate
    ) public {
        vm.assume(amount > 0.1 ether && amount < 100 ether);

        // uint256 amount = 30286446403452457539;
        bool processAfterWithdraw = true;

        address alice = address(10);
        vm.label(alice, "Alice");


        {
            deal(alice, 100000 ether);

            vm.startPrank(alice);
            (bool success,) = MC.WETH.call{value: 100000 ether}("");
            assertTrue(success, "WETH deposit failed");
            vm.stopPrank();
        }


        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();


        // Initial setup
        vm.startPrank(alice);
        IERC20(MC.WETH).approve(address(vault), amount);
        uint256 depositedShares = vault.deposit(amount, alice);
        vm.stopPrank();

        // Send WETH to buffer
        _processApprove(MC.WETH, address(vault.buffer()), amount);
        _processDeposit(address(vault.buffer()), amount);

        if (processAfterDeposit) {
            withdrawer.processAccounting();
            vault.processAccounting();

        }

        totalSupplyInvariant(initialSupply + depositedShares);
        totalAssetsInvariant(initialAssets + amount);

        // uint256 withdrawableAssets = vault.maxWithdraw(alice);

        // vm.startPrank(alice);
        // vault.withdraw(withdrawableAssets, alice, alice);
        // vm.stopPrank();

        // if (processAfterWithdraw) {
        //     withdrawer.processAccounting();
        //     vault.processAccounting();
        //     totalSupplyInvariant(initialSupply);
        //     totalAssetsInvariant(initialAssets);
        // }

        return;

        // // Allocate to ynETH
        // _processApprove(MC.WETH, address(withdrawer), amount);
        // _processWithdrawWETH(amount);
        // _processDepositAsset(address(withdrawer), MC.WETH, amount);
        // _processAllocate(address(withdrawer), MC.YNETH, amount);

        // if (processAfterAllocate) {
        //     withdrawer.processAccounting();
        //     vault.processAccounting();
        //     totalSupplyInvariant(initialSupply);
        //     totalAssetsInvariant(initialAssets);
        // }


    }
}

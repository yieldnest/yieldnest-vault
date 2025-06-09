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
contract VaultMainnetInvariantsTest is BaseIntegrationTest, TestHelper {
    using Math for uint256;


    IProvider public provider;

    function setUp() public override {
        super.setUp();
        _initVault(vault);

        provider = IProvider(vault.provider());

        // Process accounting to ensure vault is in sync
        vault.processAccounting();
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

    function _convertAssetToBase(address asset_, uint256 assets) internal view returns (uint256) {
        uint256 rate = provider.getRate(asset_);
        return assets.mulDiv(rate, 10 ** 18, Math.Rounding.Floor);
    }

    function _convertBaseToAsset(address asset_, uint256 assets) internal view returns (uint256) {
        uint256 rate = provider.getRate(asset_);
        return assets.mulDiv(10 ** 18, rate, Math.Rounding.Floor);
    }

    function test_Vault_4626Invariants_depositBase(uint256 assets) public {
        if (assets < 1e3) return; // USDC amount
        if (assets > 100_000_000e6) return;

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        uint8 decimals = vault.decimals();
        assertEq(decimals, 18, "Decimals should be 18");

        // Test the asset function
        address assetAddress = vault.asset();
        assertEq(assetAddress, MC.USDC, "Asset address should be USDC");
        
        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        // Test the convertToAssets function
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, assets, 3, "Converted assets should equal the original assets");

        uint256 previewedShares = vault.previewDeposit(assets);
        assertApproxEqAbs(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqAbs(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        // Test the depositAsset function
        address alice = address(10);
        vm.label(alice, "Alice");
        
        deal(MC.USDC, alice, assets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), assets);

        uint256 depositedShares = vault.deposit(assets, alice);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");
        vm.stopPrank();

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
        assertEq(assetAddress, MC.USDC, "Asset address should be USDC");

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
        address alice = address(10);
        vm.label(alice, "Alice");
        
        deal(MC.USDC, alice, assets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), assets);

        uint256 depositedShares = vault.depositAsset(assetAddress, assets, alice);
        assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");
        vm.stopPrank();

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }

    function test_Vault_4626Invariants_mint(uint256 shares) public {
        if (shares < 1e13) return; // at least 1 USDC worth of shares
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
        assertEq(assetAddress, MC.USDC, "Asset address should be USDC");


        // Test the convertToAssets function
        uint256 assets = vault.convertToAssets(shares);
        assertGt(assets, 0, "Assets should be greater than 0");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertApproxEqAbs(previewedAssets, assets, 3, "Previewed assets should equal the converted assets");

        // Test the mint function
        deal(MC.USDC, alice, assets);
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), assets);

        uint256 mintedAssets = vault.mint(shares, alice);
        assertEq(mintedAssets, assets, "Minted assets should equal the converted assets");
        vm.stopPrank();

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
    
    function test_Vault_4626Invariants_USDC_Donation(uint256 amount, bool processAfterWithdraw) public {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 * 1e6); // USDC has 6 decimals

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            deal(MC.USDC, address(vault), amount);

            // process accounting to update for the donation
            vault.processAccounting();

            totalSupplyInvariant(initialSupply);
            totalAssetsInvariant(initialAssets + amount);
        }
    }

    function test_Vault_4626Invariants_USDC_Deposit(uint256 amount, bool processAfterDeposit, bool processAfterWithdraw)
        public
    {
        vm.assume(amount > 100000);
        vm.assume(amount < 100_000 * 1e6); // USDC has 6 decimals

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        {
            address alice = address(10);
            deal(MC.USDC, alice, amount);

            vm.startPrank(alice);
            IERC20(MC.USDC).approve(address(vault), amount);
            uint256 depositeShares = vault.depositAsset(MC.USDC, amount, alice);
            vm.stopPrank();

            if (processAfterDeposit) {
                vault.processAccounting();
            }

            totalSupplyInvariant(initialSupply + depositeShares);
            totalAssetsInvariant(initialAssets + amount);
        }
    }

}

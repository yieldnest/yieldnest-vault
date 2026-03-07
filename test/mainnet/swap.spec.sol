// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "src/interface/IVault.sol";
import {HooksUtils} from "test/utils/HooksUtils.sol";

import {console} from "lib/forge-std/src/console.sol";

contract SwapTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        bufferStrategy = vault.buffer();
        vault.processAccounting();
    }

    function skip_test_swap_USDC_to_USDT() public {
        // call processAccounting to ensure vault is in sync
        // to account for profits and fee shares earned since last call to processAccounting
        vault.processAccounting();

        uint256 depositAmount = 100000e6;
        giveApprovalOfAssetToAugustus(MC.USDC, depositAmount);

        uint256 totalAssetsBefore = vault.totalAssets();
        depositAmount = depositAssetToVault(MC.USDC, depositAmount, 0);
        assertEq(vault.totalAssets(), depositAmount + totalAssetsBefore);

        uint256 usdtBalanceBefore = IERC20(MC.USDT).balanceOf(address(vault));
        uint256 vaultTotalAssetsBefore = vault.totalAssets();
        uint256 vaultTotalSupplyBefore = vault.totalSupply();

        PsPResponse memory response = BaseTest._fetchPSPRoute(MC.USDC, MC.USDT, depositAmount, address(vault));
        processSwap(response);
        vault.processAccounting();

        uint256 usdtBalanceAfter = IERC20(MC.USDT).balanceOf(address(vault));
        uint256 vaultTotalAssetsAfter = vault.totalAssets();

        assertTrue(usdtBalanceAfter > usdtBalanceBefore, "USDT balance should increase after swap");
        uint256 minExpectedTotalAssets =
            vaultTotalAssetsBefore * (SLIPPAGE_PRECISION - MAX_SLIPPAGE) / SLIPPAGE_PRECISION;
        assertTrue(vaultTotalAssetsAfter >= minExpectedTotalAssets, "Vault total assets should increase after swap");
    }

    function test_swap_from_USDC_to_other_supported_stable_coins() public {
        address[] memory assets = new address[](5);
        assets[0] = MC.USDT;
        assets[1] = MC.GHO;
        assets[2] = MC.USDE;
        assets[3] = MC.CRVUSD;
        assets[4] = MC.FRAX;

        HooksUtils.setMaxTotalSupplyIncreaseRatio(vault, 0.01e18);
        HooksUtils.setMaxTotalAssetsIncreaseRatio(vault, 0.01e18);
        HooksUtils.setMaxTotalAssetsDecreaseRatio(vault, 0.01e18);

        uint256 snapshotId = vm.snapshot();

        for (uint256 i = 0; i < assets.length; i++) {
            vm.revertTo(snapshotId);
            uint256 depositAmount = 1000_000e6;
            giveApprovalOfAssetToAugustus(MC.USDC, depositAmount);

            uint256 totalAssetsBefore = vault.totalAssets();
            depositAmount = depositAssetToVault(MC.USDC, depositAmount, 0);
            assertEq(vault.totalAssets(), depositAmount + totalAssetsBefore);

            uint256 assetBalanceBefore = IERC20(assets[i]).balanceOf(address(vault));
            uint256 vaultTotalAssetsBefore = vault.totalAssets();
            uint256 vaultTotalSupplyBefore = vault.totalSupply();

            PsPResponse memory response = BaseTest._fetchPSPRoute(MC.USDC, assets[i], depositAmount, address(vault));
            processSwap(response);
            vault.processAccounting();
            uint256 sharesMinted = vault.totalSupply() - vaultTotalSupplyBefore;

            uint256 assetBalanceAfter = IERC20(assets[i]).balanceOf(address(vault));
            uint256 vaultTotalAssetsAfter = vault.totalAssets();

            uint256 srcTokenRate = provider.getRate(MC.USDC);
            uint256 destTokenRate = provider.getRate(assets[i]);
            uint256 srcTokenDecimals = ERC20(MC.USDC).decimals();
            uint256 destTokenDecimals = ERC20(assets[i]).decimals();

            // Calculate expected amount without slippage first (convert from srcToken to destToken)
            uint256 expectedQuotedAmountWithoutSlippage = (depositAmount * srcTokenRate) / destTokenRate;

            if (srcTokenDecimals > destTokenDecimals) {
                expectedQuotedAmountWithoutSlippage =
                    expectedQuotedAmountWithoutSlippage / 10 ** (srcTokenDecimals - destTokenDecimals);
            } else {
                expectedQuotedAmountWithoutSlippage =
                    expectedQuotedAmountWithoutSlippage * 10 ** (destTokenDecimals - srcTokenDecimals);
            }

            // Then apply maximum slippage to get minimum required amount
            uint256 minRequiredQuotedAmount =
                (expectedQuotedAmountWithoutSlippage * (SLIPPAGE_PRECISION - MAX_SLIPPAGE)) / SLIPPAGE_PRECISION;

            assertTrue(assetBalanceAfter > assetBalanceBefore, "Asset balance should increase after swap");
            assertTrue(
                assetBalanceAfter >= minRequiredQuotedAmount, "Asset balance should be within slippage tolerance"
            );
            // asset balance should be within 0.2% of the expected amount
            assertApproxEqRel(
                vaultTotalAssetsAfter, vaultTotalAssetsBefore, 1e16, "Asset balance should be within slippage tolerance"
            );
            totalSupplyInvariant(vaultTotalSupplyBefore + sharesMinted);
        }
    }

    function depositAssetToVault(address asset, uint256 amount, uint256 assetIndex) internal returns (uint256) {
        if (!vault.getAsset(asset).active) {
            vm.startPrank(address(ADMIN));
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(assetIndex, fields);
            vm.stopPrank();
        }

        address alice = makeAddr("alice");
        uint256 balance = dealAsset(asset, alice, amount);
        vm.startPrank(alice);
        SafeERC20.forceApprove(IERC20(asset), address(vault), balance);
        vault.depositAsset(asset, balance, alice);
        vm.stopPrank();
        return balance;
    }

    function giveApprovalOfAssetToAugustus(address asset, uint256 amount) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = asset;
        values[0] = 0;
        data[0] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, amount));

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, data);
        vm.stopPrank();
    }

    function processSwap(PsPResponse memory response) internal {
        {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory data = new bytes[](1);

            targets[0] = address(response.augustus);
            values[0] = 0;
            data[0] = response.swapCalldata;

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, data);
            vm.stopPrank();
        }
    }
}

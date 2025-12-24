// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockStrategy} from "test/mainnet/mocks/MockStrategy.sol";

contract ProviderTest is BaseTest {
    Provider public provider;
    Vault public vault;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();

        // upgrade to new provider
        // Deploy a fresh Provider contract, update the Vault to use new Provider
        Provider newProvider = new Provider(address(wrappedUSDC));

        vm.startPrank(TIMELOCK);
        vault.setProvider(address(newProvider));
        vm.stopPrank();
        provider = newProvider;
    }

    function test_getRate_Of_WrappedUSDC() public view {
        assertEq(provider.getRate(address(wrappedUSDC)), 1e18);
    }

    function test_getRate_Of_USDC() public view {
        assertEq(provider.getRate(MC.USDC), 1e18);
    }

    function test_getRate_Of_USDT() public view {
        assertEq(provider.getRate(MC.USDT), 1e18);
    }

    function test_getRate_Of_GHO() public view {
        assertEq(provider.getRate(MC.GHO), 1e18);
    }

    function test_getRate_Of_USDE() public view {
        assertEq(provider.getRate(MC.USDE), 1e18);
    }

    function test_getRate_Of_CRVUSD() public view {
        assertEq(provider.getRate(MC.CRVUSD), 1e18);
    }

    function test_getRate_Of_USDS() public view {
        assertEq(provider.getRate(MC.USDS), 1e18);
    }

    function test_getRate_Of_FRAX() public view {
        assertEq(provider.getRate(MC.FRAX), 1e18);
    }

    function test_getRate_Of_SFRAX() public view {
        assertEq(provider.getRate(MC.SFRAX), IERC4626(MC.SFRAX).convertToAssets(1e18));
    }

    function test_getRate_Of_SUSDE() public view {
        assertEq(provider.getRate(MC.SUSDE), IERC4626(MC.SUSDE).convertToAssets(1e18));
    }

    function test_getRate_Of_SUSDS() public view {
        assertEq(provider.getRate(MC.SUSDS), IERC4626(MC.SUSDS).convertToAssets(1e18));
    }

    function test_getRate_Of_SCRVUSD() public view {
        assertEq(provider.getRate(MC.SCRVUSD), IERC4626(MC.SCRVUSD).convertToAssets(1e18));
    }

    function test_getRate_Of_SuperUSDCVault() public view {
        assertEq(provider.getRate(MC.SUPER_USDC_VAULT), IERC4626(MC.SUPER_USDC_VAULT).convertToAssets(1e18));
    }

    function test_getRate_Of_MorphoGauntletUSDCVault() public view {
        assertEq(
            provider.getRate(MC.MORPHO_GAUNTLET_USDC_VAULT),
            IERC4626(MC.MORPHO_GAUNTLET_USDC_VAULT).convertToAssets(1e18) * 1e12
        );
    }

    function test_getRate_Of_Withdrawer() public view {
        // The provider should return the result of IERC4626(withdrawer).convertToAssets(1e18)
        assertEq(provider.getRate(address(withdrawer)), IERC4626(address(withdrawer)).convertToAssets(1e18) * 1e12);
    }

    function test_getRate_Of_FXBASE() public view {
        // For FXBASE, provider.getRate should match the calculation in Provider.sol
        (uint256 amountYieldOut, uint256 amountStableOut) = IFxUSDBasePool(MC.FXBASE).previewRedeem(1e18);
        uint256 expectedRate =
            amountYieldOut * provider.getRate(MC.FXUSD) / 1e18 + amountStableOut * provider.getRate(MC.USDC) / 1e6;
        assertEq(provider.getRate(MC.FXBASE), expectedRate);
    }

    function test_getRate_Of_FXSAVE() public view {
        // For FXSAVE, provider.getRate should match the calculation in Provider.sol
        uint256 expectedRate = IERC4626(MC.FXSAVE).convertToAssets(1e18) * provider.getRate(MC.FXBASE) / 1e18;
        assertEq(provider.getRate(MC.FXSAVE), expectedRate);
    }

    function test_getRate_Of_FXUSD() public view {
        assertEq(provider.getRate(MC.FXUSD), 1e18);
    }

    function test_getRate_of_ArbStrategy() public view {
        assertEq(IERC4626(MC.USDC_ARB1_STRATEGY).asset(), MC.USDC);
        assertEq(IERC4626(MC.USDC_ARB1_STRATEGY).decimals(), 6);
        uint256 expectedRate = IERC4626(MC.USDC_ARB1_STRATEGY).convertToAssets(1e6) * 1e12;
        assertLt(expectedRate, 2e18);
        assertGe(expectedRate, 1e18);
        assertEq(provider.getRate(MC.USDC_ARB1_STRATEGY), expectedRate);
    }

    function test_getRate_of_FreshVaultWithUSDC() public {
        // Deploy a new BaseStrategy implementation and use a proxy for it
        // Deploy a Vault implementation with USDC as the main asset and 18 decimals behind a proxy. Do not inline the initialization.

        // Deploy the Vault implementation (not WrappedToken)
        MockStrategy implementation = new MockStrategy();

        // Deploy the TransparentUpgradeableProxy, but don't inline the call to initialize
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");

        // Now initialize behind the proxy. Use the MockStrategy's initializer.
        string memory name = "Test Wrapped USDC";
        string memory symbol = "tUSDC";
        address asset = MC.USDC;
        uint8 decimals = 18;

        MockStrategy(payable(address(proxy))).initialize(
            address(this), // admin
            name,
            symbol,
            decimals,
            0, // baseWithdrawalFee_
            false, // countNativeAsset_
            false, // alwaysComputeTotalAssets_
            1 // defaultAssetIndex_
        );

        // Use MockStrategy interface for rate tests
        MockStrategy testVault = MockStrategy(payable(address(proxy)));

        testVault.grantRole(testVault.ASSET_MANAGER_ROLE(), address(this));
        testVault.grantRole(testVault.PROVIDER_MANAGER_ROLE(), address(this));

        testVault.addAsset(address(wrappedUSDC), false);
        testVault.addAsset(asset, true);
        testVault.setProvider(address(provider));

        // Expect the rate for this new vault (should be 1:1 with underlying for a fresh vault)
        // Use the already deployed provider instance
        assertEq(provider.getRate(address(testVault)), 1e18);
    }
}

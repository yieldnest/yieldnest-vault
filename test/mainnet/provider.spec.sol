// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626} from "src/Common.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {IStETH, IMETH, IRETH, IynLSDe} from "src/interface/IProvider.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "src/Common.sol";
import {Vault} from "src/Vault.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";

import {IswETH, IsfrxETH, IFrxEthWethDualOracle, ICurveLpConnector} from "src/interface/IProvider.sol";

contract ProviderTest is BaseIntegrationTest, Etches {
    Provider public provider;
    address public admin = makeAddr("admin");
    MockStrategy public mockStrategy;

    function setUp() public override {
        super.setUp();
        provider = Provider(vault.provider());

        MockStrategy implementation = new MockStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), admin, "");
        mockStrategy = MockStrategy(payable(address(proxy)));
        mockStrategy.initialize(
            "Mock WETH Strategy",
            "mWETH",
            admin,
            true, // alwaysComputeTotalAssets
            0 // defaultAssetIndex
        );

        vm.startPrank(admin);
        mockStrategy.grantRole(mockStrategy.ASSET_MANAGER_ROLE(), admin);
        mockStrategy.addAsset(MC.WETH, true);
        vm.stopPrank();

        assertEq(
            mockStrategy.hasRole(mockStrategy.DEFAULT_ADMIN_ROLE(), admin), true, "Admin should have DEFAULT_ADMIN_ROLE"
        );

        vm.startPrank(admin);
        mockStrategy.grantRole(mockStrategy.PROVIDER_MANAGER_ROLE(), admin);
        vm.stopPrank();

        // Deploy a new Provider instance
        Provider newProvider = new Provider();

        // Set the new provider in the mock strategy
        vm.prank(admin);
        mockStrategy.setProvider(address(newProvider));
    }

    function test_Provider_GetRateWETH() public view {
        uint256 rate = provider.getRate(MC.WETH);
        assertEq(rate, 1e18, "Rate for WETH should be 1e18");
    }

    function test_Provider_GetRateSTETH() public view {
        uint256 rate = provider.getRate(MC.STETH);
        uint256 expectedPrice = 1e18;
        assertEq(rate, expectedPrice, "Rate for STETH should be 1e18");
    }

    function test_Provider_GetRateYNETH() public view {
        uint256 expectedRate = IERC4626(MC.YNETH).convertToAssets(1e18);
        uint256 rate = provider.getRate(MC.YNETH);
        assertEq(rate, expectedRate, "Rate for YNETH should match the convertToAssets rate");
    }

    function test_Provider_GetRateYNLSDE() public view {
        uint256 expectedRate = IynLSDe(MC.YNLSDE).previewRedeem(1e18);
        uint256 rate = provider.getRate(MC.YNLSDE);
        assertEq(rate, expectedRate, "Rate for YNLSDE should match the convertToAssets rate");
    }

    function test_Provider_GetRateBUFFER() public view {
        uint256 expectedRate = IERC4626(vault.buffer()).convertToAssets(1e18);
        uint256 rate = provider.getRate(vault.buffer());
        assertEq(rate, expectedRate, "Rate for BUFFER should match the convertToAssets rate");
    }

    function test_Provider_GetRateWSTETH() public view {
        uint256 expectedRate = IStETH(MC.STETH).getPooledEthByShares(1e18);
        uint256 rate = provider.getRate(MC.WSTETH);
        assertEq(rate, expectedRate, "Rate for WSTETH should match the getPooledEthByShares rate");
    }

    function test_Provider_GetRateMETH() public view {
        uint256 expectedRate = IMETH(MC.METH_STAKING_MANAGER).mETHToETH(1e18);
        uint256 rate = provider.getRate(MC.METH);
        assertEq(rate, expectedRate, "Rate for METH should match the ratio");
    }

    function test_Provider_GetRateRETH() public view {
        uint256 expectedRate = IRETH(MC.RETH).getExchangeRate();
        uint256 rate = provider.getRate(MC.RETH);
        assertEq(rate, expectedRate, "Rate for RETH should match the getExchangeRate rate");
    }

    function test_Provider_GetRateSWELL() public view {
        uint256 expectedRate = IswETH(MC.SWELL).swETHToETHRate();
        uint256 rate = provider.getRate(MC.SWELL);
        assertEq(rate, expectedRate, "Rate for SWELL should match the swETHToETHRate");
    }

    function test_Provider_GetRateSFRXETH() public view {
        uint256 frxETHPriceInETH = IFrxEthWethDualOracle(MC.FRX_ETH_WETH_DUAL_ORACLE).getCurveEmaEthPerFrxEth();
        uint256 expectedRate = IsfrxETH(MC.SFRXETH).pricePerShare() * frxETHPriceInETH / 1e18;
        uint256 rate = provider.getRate(MC.SFRXETH);
        assertEq(rate, expectedRate, "Rate for SFRXETH should match the combined rate");
    }

    function test_Provider_GetRateOETH() public view {
        uint256 rate = provider.getRate(MC.OETH);
        assertEq(rate, 1e18, "Rate for OETH should be 1e18");
    }

    function test_Provider_GetRateWOETH() public view {
        uint256 expectedRate = IERC4626(MC.WOETH).convertToAssets(1e18);
        uint256 rate = provider.getRate(MC.WOETH);
        assertEq(rate, expectedRate, "Rate for WOETH should match the convertToAssets rate");
    }

    function test_Provider_GetRateSmokehouseWSTETH() public view {
        uint256 expectedRate =
            IStETH(MC.STETH).getPooledEthByShares(IERC4626(MC.SMOKEHOUSE_WSTETH).convertToAssets(1e18));
        uint256 rate = provider.getRate(MC.SMOKEHOUSE_WSTETH);
        assertEq(rate, expectedRate, "Rate for SMOKEHOUSE_WSTETH should match the combined rate");
    }

    function test_Provider_GetRateCurveLpStrategy() public view {
        (int256 strategyRate,) = ICurveLpConnector(MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR).rate();
        uint256 expectedRate = uint256(strategyRate);
        uint256 rate = provider.getRate(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY);
        assertEq(rate, expectedRate, "Rate for Curve LP Strategy should match the connector rate");
    }

    function test_Provider_GetRateCurveLpStrategy_RateIsNegative() public {
        vm.mockCall(
            MC.CURVE_LP_YNETH_YNLSDE_CONNECTOR,
            abi.encodeWithSelector(ICurveLpConnector.rate.selector),
            abi.encode(-1, 0)
        );
        vm.expectRevert(Provider.RateIsNegative.selector);
        provider.getRate(MC.CURVE_LP_YNETH_YNLSDE_STRATEGY);
    }

    function test_Provider_GetRateEulerWETH22Vault() public view {
        uint256 expectedRate = IERC4626(MC.EULER_WETH_22_VAULT).convertToAssets(1e18);
        uint256 rate = provider.getRate(MC.EULER_WETH_22_VAULT);
        assertEq(rate, expectedRate, "Rate for EULER_WETH_22_VAULT should match the convertToAssets rate");
    }

    function test_Provider_GetRateMockStrategy() public view {
        uint256 expectedRate = IERC4626(address(mockStrategy)).convertToAssets(1e18);
        uint256 rate = provider.getRate(address(mockStrategy));
        assertEq(rate, expectedRate, "Rate for WETH strategy should match the convertToAssets rate");
    }

    function test_Provider_GetRateMockStrategy_AfterDeposit() public {
        // Deposit 1 ETH worth of WETH into strategy
        deal(MC.WETH, address(this), 1e18);
        IERC20(MC.WETH).approve(address(mockStrategy), 1e18);
        IERC4626(mockStrategy).deposit(1e18, address(this));

        uint256 expectedRate = IERC4626(mockStrategy).convertToAssets(1e18);
        uint256 rate = provider.getRate(address(mockStrategy));
        assertEq(rate, expectedRate, "Rate for WETH strategy should match the convertToAssets rate after deposit");
    }

    function test_Provider_GetRateWstETHStrategy() public {
        // Create and initialize a new mock strategy with WSTETH as asset
        MockStrategy wstethStrategy = MockStrategy(
            payable(address(new TransparentUpgradeableProxy(address(new MockStrategy()), address(this), "")))
        );
        // Set the default asset index to 0, so WSTETH is the default asset
        wstethStrategy.initialize("Mock wstETH Strategy", "mWSTETH", address(this), false, 0);

        // Grant admin role to this contract
        wstethStrategy.grantRole(wstethStrategy.ASSET_MANAGER_ROLE(), address(this));
        wstethStrategy.grantRole(wstethStrategy.PROVIDER_MANAGER_ROLE(), address(this));

        // Add WSTETH as an asset
        wstethStrategy.addAsset(MC.WSTETH, true);

        // Create a new provider instance and set it for the strategy
        Provider newProvider = new Provider();
        wstethStrategy.setProvider(address(newProvider));

        // Deposit 1 WSTETH into strategy
        deal(MC.WSTETH, address(this), 1e18);
        IERC20(MC.WSTETH).approve(address(wstethStrategy), 1e18);
        IERC4626(wstethStrategy).deposit(1e18, address(this));
        vm.expectRevert(abi.encodeWithSelector(Provider.UnsupportedAsset.selector, address(wstethStrategy)));
        provider.getRate(address(wstethStrategy));
    }

    function test_Provider_UnsupportedAsset() public {
        address unsupportedAsset = address(0x123);
        vm.expectRevert();
        provider.getRate(unsupportedAsset);
    }

    function test_Provider_AllAssetsHaveRate() public view {
        address[] memory assets = vault.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            uint256 rate = provider.getRate(assets[i]);
            // The rate should be nonzero for supported assets
            assertGt(rate, 0, "Asset should have a nonzero rate");
        }
    }
}

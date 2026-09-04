// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626} from "src/Common.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {MockStrategy} from "test/mainnet/mocks/MockStrategy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "src/Common.sol";
import {Vault} from "src/Vault.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";

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
            "Mock USDE Strategy",
            "mUSDE",
            admin,
            true, // alwaysComputeTotalAssets
            0 // defaultAssetIndex
        );

        vm.startPrank(admin);
        mockStrategy.grantRole(mockStrategy.ASSET_MANAGER_ROLE(), admin);
        mockStrategy.addAsset(MC.USDE, true);
        vm.stopPrank();

        assertEq(
            mockStrategy.hasRole(mockStrategy.DEFAULT_ADMIN_ROLE(), admin), true, "Admin should have DEFAULT_ADMIN_ROLE"
        );

        vm.startPrank(admin);
        mockStrategy.grantRole(mockStrategy.PROVIDER_MANAGER_ROLE(), admin);
        vm.stopPrank();

        // Deploy a new Provider instance
        Provider newProvider = new Provider(address(wusdc), MC.FLEX_STRATEGY_USDC);

        // Set the new provider in the mock strategy
        vm.prank(admin);
        mockStrategy.setProvider(address(newProvider));
    }

    function test_Provider_GetRateUSDC() public view {
        uint256 rate = provider.getRate(MC.USDC);
        assertEq(rate, 1e18, "Rate for USDC should be 1e18");
    }

    function test_Provider_GetRateWUSDC() public view {
        uint256 rate = provider.getRate(address(wusdc));
        assertEq(rate, 1e18, "Rate for WUSDC should be 1e18");
    }

    function test_Provider_GetRate_FLEX_STRATEGY_USDC() public view {
        uint256 rate = provider.getRate(MC.FLEX_STRATEGY_USDC);
        assertGt(rate, 1e18, "Rate for FLEX_STRATEGY_USDC should be 1e18");
        assertLt(rate, 2e18, "Rate for FLEX_STRATEGY_USDC should be less than 1.1e18");
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {IERC4626} from "src/Common.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract ProviderTest is BaseTest {
    Provider public provider;

    function setUp() public {
        (, provider) = BaseTest.deploy();
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
}

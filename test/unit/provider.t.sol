// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626, ERC20} from "src/Common.sol";

contract MockWUSDC is ERC20 {
    constructor() ERC20("Wrapped USDC", "WUSDC") {}
}

contract MockERC4626Strategy {
    address public asset;
    uint8 public decimals;
    uint256 public rate = 1.05e18;

    constructor(address _asset, uint8 _decimals) {
        asset = _asset;
        decimals = _decimals;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * rate / 1e18;
    }
}

contract ProviderTest is Test {
    Provider public provider;
    MockWUSDC public wusdc;
    MockERC4626Strategy public strategy;
    address public admin = makeAddr("admin");

    function setUp() public {
        wusdc = new MockWUSDC();
        strategy = new MockERC4626Strategy(MC.USDC, 6);
        provider = new Provider(address(wusdc), address(strategy));
    }

    function test_Provider_GetRateUSDC() public view {
        uint256 rate = provider.getRate(MC.USDC);
        assertEq(rate, 1e18, "USDC rate should be 1e18");
    }

    function test_Provider_GetRateWUSDC() public view {
        uint256 rate = provider.getRate(address(wusdc));
        assertEq(rate, 1e18, "WUSDC rate should be 1e18");
    }

    function test_Provider_GetRateStrategy() public view {
        uint256 rate = provider.getRate(address(strategy));
        assertEq(rate, 1.05e18, "Strategy rate should be its convertToAssets(1e18)");
    }

    function test_Provider_GetRateUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        vm.expectRevert(abi.encodeWithSelector(Provider.UnsupportedAsset.selector, unsupportedAsset));
        provider.getRate(unsupportedAsset);
    }

    function test_Provider_ValidStrategies() public {
        address[4] memory assets = [MC.USDC, MC.USDT, MC.USDS, MC.USDE];
        uint8[4] memory decimals = [6, 6, 18, 18];

        for (uint256 i = 0; i < assets.length; i++) {
            MockERC4626Strategy validStrategy = new MockERC4626Strategy(assets[i], decimals[i]);
            Provider validProvider = new Provider(address(wusdc), address(validStrategy));
            assertEq(
                validProvider.getRate(address(validStrategy)),
                1.05e18,
                "Strategy rate should be its convertToAssets(1e18)"
            );
        }
    }

    function test_Provider_InvalidStrategyAsset() public {
        address unknownAsset = makeAddr("unknownAsset");
        MockERC4626Strategy badStrategy = new MockERC4626Strategy(unknownAsset, 18);
        vm.expectRevert(
            abi.encodeWithSelector(Provider.InvalidStrategy.selector, address(badStrategy), unknownAsset, 18)
        );
        new Provider(address(wusdc), address(badStrategy));
    }

    function test_Provider_InvalidStrategyDecimals() public {
        MockERC4626Strategy badUsdcStrategy = new MockERC4626Strategy(MC.USDC, 18);
        vm.expectRevert(
            abi.encodeWithSelector(Provider.InvalidStrategy.selector, address(badUsdcStrategy), MC.USDC, 18)
        );
        new Provider(address(wusdc), address(badUsdcStrategy));

        MockERC4626Strategy badUsdeStrategy = new MockERC4626Strategy(MC.USDE, 6);
        vm.expectRevert(abi.encodeWithSelector(Provider.InvalidStrategy.selector, address(badUsdeStrategy), MC.USDE, 6));
        new Provider(address(wusdc), address(badUsdeStrategy));
    }
}

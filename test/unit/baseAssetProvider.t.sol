// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {BaseAssetProvider} from "src/module/BaseAssetProvider.sol";

contract BaseAssetProviderTest is Test {
    BaseAssetProvider public provider;
    address public baseAsset = makeAddr("baseAsset");
    address public defaultAsset = makeAddr("defaultAsset");
    uint256 public baseAssetRate = 1e18;
    uint256 public defaultAssetRate = 0.999e18;

    function setUp() public {
        provider = new BaseAssetProvider(baseAsset, baseAssetRate, defaultAsset, defaultAssetRate);
    }

    function test_BaseAssetProvider_ConstructorSetsParams() public view {
        assertEq(provider.baseAsset(), baseAsset);
        assertEq(provider.baseAssetRate(), baseAssetRate);
        assertEq(provider.defaultAsset(), defaultAsset);
        assertEq(provider.defaultAssetRate(), defaultAssetRate);
    }

    function test_BaseAssetProvider_GetRateBaseAsset() public view {
        assertEq(provider.getRate(baseAsset), baseAssetRate);
    }

    function test_BaseAssetProvider_GetRateDefaultAsset() public view {
        assertEq(provider.getRate(defaultAsset), defaultAssetRate);
    }

    function test_BaseAssetProvider_GetRateUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupportedAsset");

        vm.expectRevert(abi.encodeWithSelector(BaseAssetProvider.UnsupportedAsset.selector, unsupportedAsset));
        provider.getRate(unsupportedAsset);
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {BaseAssetProvider} from "src/module/BaseAssetProvider.sol";

contract BaseAssetProviderTest is Test {
    BaseAssetProvider public provider;
    address public baseAsset = makeAddr("baseAsset");
    uint256 public rate = 1e18;

    function setUp() public {
        provider = new BaseAssetProvider(baseAsset, rate);
    }

    function test_BaseAssetProvider_ConstructorSetsParams() public view {
        assertEq(provider.baseAsset(), baseAsset);
        assertEq(provider.rate(), rate);
    }

    function test_BaseAssetProvider_GetRateBaseAsset() public view {
        assertEq(provider.getRate(baseAsset), rate);
    }

    function test_BaseAssetProvider_GetRateUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupportedAsset");

        vm.expectRevert(abi.encodeWithSelector(BaseAssetProvider.UnsupportedAsset.selector, unsupportedAsset));
        provider.getRate(unsupportedAsset);
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626} from "src/Common.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {IBNBXStakeManagerV2} from "src/interface/external/stader/IBNBXStakeManagerV2.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";

contract ProviderTest is Test, Etches {
    Provider public provider;

    function setUp() public {
        provider = new Provider();
        mockBuffer();
    }

    function test_Provider_GetRateWBNB() public view {
        uint256 rate = provider.getRate(MC.WBNB);
        assertEq(rate, 1e18, "Rate for WBNB should be 1e18");
    }

    function test_Provider_GetRateYNBNBk() public view {
        uint256 expectedRate = IERC4626(MC.YNBNBK).previewRedeem(1e18);
        uint256 rate = provider.getRate(MC.YNBNBK);
        assertEq(rate, expectedRate, "Rate for YNBNBk should match the previewRedeem rate");
    }

    function test_Provider_GetRateBUFFER() public view {
        uint256 expectedRate = IERC4626(MC.BUFFER).previewRedeem(1e18);
        uint256 rate = provider.getRate(MC.BUFFER);
        assertEq(rate, expectedRate, "Rate for BUFFER should match the previewRedeem rate");
    }

    function test_Provider_GetRateBNBx() public view {
        uint256 expectedRate = IBNBXStakeManagerV2(MC.BNBX_STAKE_MANAGER).convertBnbXToBnb(1e18);
        uint256 rate = provider.getRate(MC.BNBX);
        assertEq(rate, expectedRate, "Rate for BNBx should match the ratio");
    }

    function test_Provider_UnsupportedAsset() public {
        address unsupportedAsset = address(0x123);
        vm.expectRevert();
        provider.getRate(unsupportedAsset);
    }
}

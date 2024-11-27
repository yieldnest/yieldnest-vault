// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626} from "src/Common.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {IStETH, IMETH, IOETH, IRETH, IswETH, IChainlinkAggregator} from "src/interface/IProvider.sol";

contract ProviderTest is Test, Etches {
    Provider public provider;

    function setUp() public {
        provider = new Provider();
        mockBuffer();
    }

    function test_Provider_GetRateWETH() public view {
        uint256 rate = provider.getRate(MC.WETH);
        assertEq(rate, 1e18, "Rate for WETH should be 1e18");
    }

    function test_Provider_GetRateSTETH() public view {
        uint256 rate = provider.getRate(MC.STETH);
        uint256 expectedPrice = uint256(IChainlinkAggregator(MC.CL_STETH_FEED).latestAnswer());
        assertEq(rate, expectedPrice, "Rate for STETH should be 1e18");
    }

    function test_Provider_GetRateYNETH() public view {
        uint256 expectedRate = IERC4626(MC.YNETH).previewRedeem(1e18);
        uint256 rate = provider.getRate(MC.YNETH);
        assertEq(rate, expectedRate, "Rate for YNETH should match the previewRedeem rate");
    }

    function test_Provider_GetRateYNLSDE() public view {
        uint256 expectedRate = IERC4626(MC.YNLSDE).previewRedeem(1e18);
        uint256 rate = provider.getRate(MC.YNLSDE);
        assertEq(rate, expectedRate, "Rate for YNLSDE should match the previewRedeem rate");
    }

    function test_Provider_GetRateBUFFER() public view {
        uint256 expectedRate = IERC4626(MC.BUFFER).previewRedeem(1e18);
        uint256 rate = provider.getRate(MC.BUFFER);
        assertEq(rate, expectedRate, "Rate for BUFFER should match the previewRedeem rate");
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

    function test_Provider_UnsupportedAsset() public {
        address unsupportedAsset = address(0x123);
        vm.expectRevert();
        provider.getRate(unsupportedAsset);
    }
}
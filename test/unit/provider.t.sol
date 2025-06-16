// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC4626, ERC20} from "src/Common.sol";

contract MockWUSDC is ERC20 {
    constructor() ERC20("Wrapped USDC", "WUSDC") {}
}

contract ProviderTest is Test {
    Provider public provider;
    MockWUSDC public wusdc;
    address public admin = makeAddr("admin");

    function setUp() public {
        wusdc = new MockWUSDC();
        provider = new Provider(address(wusdc));
    }

    function test_Provider_GetRateUSDC() public view {
        uint256 rate = provider.getRate(MC.USDC);
        assertEq(rate, 1e18, "USDC rate should be 1e18");
    }

    function test_Provider_GetRateWUSDC() public view {
        uint256 rate = provider.getRate(address(wusdc));
        assertEq(rate, 1e18, "WUSDC rate should be 1e18");
    }

    function test_Provider_GetRateUnsupportedAsset() public {
        address unsupportedAsset = makeAddr("unsupported");
        vm.expectRevert(abi.encodeWithSelector(Provider.UnsupportedAsset.selector, unsupportedAsset));
        provider.getRate(unsupportedAsset);
    }
}

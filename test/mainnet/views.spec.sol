// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {ViewUtils} from "test/utils/ViewUtils.sol";
import {MockERC4626, ERC20} from "test/mainnet/mocks/MockERC4626.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {IVault} from "src/interface/IVault.sol";
import {console} from "forge-std/console.sol";

contract ViewUtilsTest is BaseIntegrationTest {
    function setUp() public override {
        super.setUp();
    }

    function test_BasicViews() public {
        console.log("DEBUG STATEMENT");

        console.log("totalSupply", vault.totalSupply());
        console.log("totalAssets", vault.totalAssets());
        console.log("convertToAssets", vault.convertToAssets(1e18));
        console.log(" totalAssets * 1e18 / totalSupply", vault.totalAssets() * 1e18 / vault.totalSupply());
    }
}

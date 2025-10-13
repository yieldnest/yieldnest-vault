// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract VaultViewsTest is BaseTest {
    Vault public vault;

    function setUp() public {
        (vault,) = BaseTest.deploy();
        vault.processAccounting();
    }

    function test_default_asset_views() public view {
        address defaultAsset = vault.asset();
        uint256 totalAssets = vault.totalAssets();
        uint256 totalBaseAssets = vault.totalBaseAssets();

        assertEq(defaultAsset, MC.USDC, "Default asset should be USDC");

        // totalAssets and totalBaseAssets should not fail and should be non-negative
        assertGe(totalAssets, 0, "totalAssets should be non-negative");
        assertGe(totalBaseAssets, 0, "totalBaseAssets should be non-negative");
    }

    function test_vault_metadata() public view {
        string memory name = vault.name();
        string memory symbol = vault.symbol();
        uint8 decimals = vault.decimals();

        assertEq(name, "ynUSD Max", "Vault name should be ynUSDx");
        assertEq(symbol, "ynUSDx", "Vault symbol should be ynUSDx");
        assertEq(decimals, 18, "Vault decimals should be 18");

        assertEq(vault.VAULT_VERSION(), "0.4.0", "Vault version should be 0.4.0");
    }

    function test_vault_configuration() public view {
        assertEq(vault.paused(), false, "Vault should not be paused");
        assertEq(vault.alwaysComputeTotalAssets(), false, "Vault should not always compute total assets");
        assertEq(vault.countNativeAsset(), false, "Vault should not count native asset");
    }
}

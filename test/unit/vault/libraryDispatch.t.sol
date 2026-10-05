// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";

contract AccountingOverrideVault is Vault {
    uint256 public additionalAssets;

    function setAdditionalAssets(uint256 additionalAssets_) external {
        additionalAssets = additionalAssets_;
    }

    function computeTotalAssets() public view override returns (uint256) {
        return super.computeTotalAssets() + additionalAssets;
    }
}

contract VaultLibDispatchUnitTest is Test {
    function test_processAccounting_usesComputeTotalAssetsOverride() public {
        AccountingOverrideVault implementation = new AccountingOverrideVault();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");
        AccountingOverrideVault vault = AccountingOverrideVault(payable(address(proxy)));
        vault.initialize(address(this), "Test Vault", "TEST", 18, 0, false, false, 0);

        MockERC20 asset = new MockERC20("Test Asset", "TEST");
        MockProvider provider = new MockProvider();
        provider.setRate(address(asset), 1e18);

        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), address(this));
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), address(this));
        vault.setProvider(address(provider));
        vault.addAsset(address(asset), true);
        vault.setAdditionalAssets(100 ether);
        vault.processAccounting();

        assertEq(vault.totalBaseAssets(), 100 ether);
        assertEq(vault.totalBaseAssets(), vault.computeTotalAssets());
    }
}

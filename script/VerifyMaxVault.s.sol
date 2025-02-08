// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault} from "src/BaseVault.sol";
import {BaseVerifyScript} from "script/BaseVerifyScript.sol";
import {console} from "lib/forge-std/src/console.sol";
import {MaxVaultViewer} from "src/utils/MaxVaultViewer.sol";

// FOUNDRY_PROFILE=mainnet forge script VerifyMaxVault
contract VerifyMaxVault is BaseVerifyScript {
    function symbol() public view virtual override returns (string memory) {
        return "ynETHx";
    }

    function run() public {
        _loadDeployment();
        _setup();

        verify();
    }

    function verify() public view {
        assertNotEq(address(vault), address(0), "vault is not set");

        assertEq(vault.name(), "ynETH MAX", "name is invalid");
        assertEq(vault.symbol(), "ynETHx", "symbol is invalid");
        assertEq(vault.decimals(), 18, "decimals is invalid");
        assertEq(vault.provider(), address(rateProvider), "provider is invalid");
        assertEq(vault.baseWithdrawalFee(), 100000, "base withdrawal fee is invalid");
        assertEq(vault.countNativeAsset(), true, "count native asset is invalid");
        assertFalse(vault.alwaysComputeTotalAssets(), "always compute total assets is invalid");
        IVault.AssetParams memory asset;
        address[] memory assets = vault.getAssets();

        assertEq(assets[0], contracts.WETH(), "assets[0] is invalid");

        asset = vault.getAsset(contracts.WETH());
        assertEq(asset.decimals, 18, "asset[0].decimals is invalid");
        assertEq(asset.active, true, "asset[0].active is invalid");
        assertEq(asset.index, 0, "asset[0].index is invalid");

        console.log("Verifying WETH deposit and withdraw rules.");
        _verifyWethWithdrawRule(vault, contracts.WETH());
        _verifyWethDepositRule(vault, contracts.WETH());

        // TODO: Add rest of assertions and verifications

        assertFalse(vault.paused());

        _verifyDefaultRoles();
        _verifyTemporaryRoles();

        console.log("Verifying viewer.");
        _verifyViewer();
        assertTrue(
            MaxVaultViewer(address(viewer)).isUnderlyingAsset(contracts.WETH()), "WETH is not an underlying asset"
        );
    }

    function _checkForAsset(address asset) internal view returns (bool isIncluded, uint256 index) {
        address[] memory assets = vault.getAssets();

        for (uint256 i; i < assets.length;) {
            if (assets[i] == asset) {
                isIncluded = true;
                index = i;
                break;
            }
            {
                i++;
            }
        }
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "src/Common.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Test, IMockERC20} from "lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title ERC4626ComplianceTest
 * @notice Helper contract for testing ERC4626 compliance
 * @dev This contract provides utility functions to test ERC4626 vault compliance
 */
abstract contract ERC4626ComplianceTest is ERC4626Test {
    /**
     * @notice Returns the vault to test
     * @return The ERC4626 vault implementation
     */
    function getVault() internal view virtual returns (IERC4626);

    function setUpVault(Init memory init) public virtual override {
        // Get the underlying token's decimals to properly handle token amounts
        uint8 underlyingDecimals = IERC20Metadata(_underlying_).decimals();

        // Bound the yield to 0 as per instructions
        // This ensures no yield is applied during the test setup
        init.yield = 0;

        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));

            // Bound share and asset values to reasonable amounts based on token decimals
            // to avoid overflow and unrealistic test scenarios
            init.share[i] = bound(init.share[i], 0, 1_000_000 * (10 ** underlyingDecimals));
            init.asset[i] = bound(init.asset[i], 0, 1_000_000 * (10 ** underlyingDecimals));

            // shares
            uint256 shares = init.share[i];
            deal(_underlying_, user, shares);
            _approve(_underlying_, user, _vault_, shares);
            vm.prank(user);
            try IERC4626(_vault_).deposit(shares, user) {}
            catch {
                vm.assume(false);
            }
            // assets
            uint256 assets = init.asset[i];
            deal(_underlying_, user, assets);
        }

        // setup initial yield for vault
        // setUpYield(init);
    }

    /**
     * @notice Tests that previewDeposit returns the correct number of shares
     * @param assets The amount of assets to deposit
     */
    function test_previewDeposit_correctShares(uint256 assets) public view {
        // Bound assets to a reasonable maximum to avoid overflow
        assets = bound(assets, 0, 1000_000_000e18);

        IERC4626 vault = getVault();
        uint256 shares = vault.previewDeposit(assets);
        uint256 expectedShares = vault.convertToShares(assets);

        assertEq(shares, expectedShares, "Preview deposit should return correct shares amount");
    }
}

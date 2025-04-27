// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "src/Common.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Test, IMockERC20} from "lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVault} from "src/interface/IVault.sol";

/**
 * @title ERC4626ComplianceTest
 * @notice Helper contract for testing ERC4626 compliance
 * @dev This contract provides utility functions to test ERC4626 vault compliance
 */
abstract contract ERC4626ComplianceTest is ERC4626Test {
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

    function testFail_withdraw(Init memory init, uint256 assets) public virtual override {
        vm.skip(true);
    }

    function testFail_redeem(Init memory init, uint256 assets) public virtual override {
        vm.skip(true);
    }

    function test_withdraw_fails(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        assets = bound(assets, 0, _max_withdraw(owner));
        vm.assume(caller != owner);
        vm.assume(assets > 0);
        _approve(_vault_, owner, caller, 0);
        vm.prank(caller);

        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxWithdraw.selector, owner, assets, 0));
        uint256 shares = IERC4626(_vault_).withdraw(assets, receiver, owner);
    }

    function test_redeem_fails(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        shares = bound(shares, 0, _max_redeem(owner));
        vm.assume(caller != owner);
        vm.assume(shares > 0);
        _approve(_vault_, owner, caller, 0);
        vm.expectRevert(abi.encodeWithSelector(IVault.ExceededMaxRedeem.selector, owner, shares, 0));
        vm.prank(caller);
        IERC4626(_vault_).redeem(shares, receiver, owner);
    }
}

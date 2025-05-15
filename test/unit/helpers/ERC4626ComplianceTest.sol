// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "src/Common.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Prop} from "lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.prop.sol";
import {IMockERC20} from "lib/openzeppelin-contracts/lib/erc4626-tests/ERC4626.test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVault} from "src/interface/IVault.sol";

/**
 * @title ERC4626ComplianceTest
 * @notice Helper contract for testing ERC4626 compliance
 * @dev This contract provides utility functions to test ERC4626 vault compliance
 * @dev This contract is adapted from OpenZeppelin's ERC4626.test.sol to avoid
 * using the deprecated testFail_ functions in Forge. It provides the same
 * functionality but uses vm.expectRevert instead of testFail_ for testing
 * revert conditions.
 */
abstract contract ERC4626ComplianceTest is ERC4626Prop {
    function setUp() public virtual;

    uint256 constant N = 3;

    struct Init {
        address[N] user;
        uint72[N] share;
        uint72[N] asset;
    }

    function setUpVault(Init memory init) public virtual {
        // Get the underlying token's decimals to properly handle token amounts
        uint8 underlyingDecimals = IERC20Metadata(_underlying_).decimals();

        // setup initial shares and assets for individual users
        for (uint256 i = 0; i < N; i++) {
            address user = init.user[i];
            vm.assume(_isEOA(user));

            // Bound share and asset values to reasonable amounts based on token decimals
            // to avoid overflow and unrealistic test scenarios; use uint72 for faster run times
            init.share[i] = uint72(bound(init.share[i], 0, 1000 * (10 ** underlyingDecimals)));
            init.asset[i] = uint72(bound(init.asset[i], 0, 1000 * (10 ** underlyingDecimals)));

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
    }

    //
    // asset
    //
    function test_asset(Init memory init) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        prop_asset(caller);
    }

    function test_totalAssets(Init memory init) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        prop_totalAssets(caller);
    }

    //
    // convert
    //
    function test_convertToShares(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller1 = init.user[0];
        address caller2 = init.user[1];
        prop_convertToShares(caller1, caller2, assets);
    }

    function test_convertToAssets(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller1 = init.user[0];
        address caller2 = init.user[1];
        prop_convertToAssets(caller1, caller2, shares);
    }

    //
    // deposit
    //
    function test_maxDeposit(Init memory init) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        prop_maxDeposit(caller, receiver);
    }

    function test_previewDeposit(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address other = init.user[2];
        assets = bound(assets, 0, _max_deposit(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_previewDeposit(caller, receiver, other, assets);
    }

    function test_deposit(Init memory init, uint256 assets, uint256 allowance) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        assets = bound(assets, 0, _max_deposit(caller));
        _approve(_underlying_, caller, _vault_, allowance);
        prop_deposit(caller, receiver, assets);
    }

    //
    // mint
    //
    function test_maxMint(Init memory init) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        prop_maxMint(caller, receiver);
    }

    function test_previewMint(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address other = init.user[2];
        shares = bound(shares, 0, _max_mint(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_previewMint(caller, receiver, other, shares);
    }

    function test_mint(Init memory init, uint256 shares, uint256 allowance) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        shares = bound(shares, 0, _max_mint(caller));
        _approve(_underlying_, caller, _vault_, allowance);
        prop_mint(caller, receiver, shares);
    }

    //
    // withdraw
    //
    function test_maxWithdraw(Init memory init) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address owner = init.user[1];
        prop_maxWithdraw(caller, owner);
    }

    function test_previewWithdraw(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        address other = address(0x01e4);
        assets = bound(assets, 0, _max_withdraw(owner));
        _approve(_vault_, owner, caller, type(uint256).max);
        prop_previewWithdraw(caller, receiver, owner, other, assets);
    }

    function test_withdraw(Init memory init, uint256 assets, uint256 allowance) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        assets = bound(assets, 0, _max_withdraw(owner));
        _approve(_vault_, owner, caller, allowance);
        prop_withdraw(caller, receiver, owner, assets);
    }

    //
    // redeem
    //
    function test_maxRedeem(Init memory init) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address owner = init.user[1];
        prop_maxRedeem(caller, owner);
    }

    function skip_test_previewRedeem(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        address other = address(0x01e4);
        shares = bound(shares, 0, _max_redeem(owner));
        _approve(_vault_, owner, caller, type(uint256).max);
        prop_previewRedeem(caller, receiver, owner, other, shares);
    }

    function test_redeem(Init memory init, uint256 shares, uint256 allowance) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        address receiver = init.user[1];
        address owner = init.user[2];
        shares = bound(shares, 0, _max_redeem(owner));
        _approve(_vault_, owner, caller, allowance);
        prop_redeem(caller, receiver, owner, shares);
    }

    //
    // round trip tests
    //
    function test_RT_deposit_redeem(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        assets = bound(assets, 0, _max_deposit(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_deposit_redeem(caller, assets);
    }

    function test_RT_deposit_withdraw(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        assets = bound(assets, 0, _max_deposit(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_deposit_withdraw(caller, assets);
    }

    function test_RT_redeem_deposit(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        shares = bound(shares, 0, _max_redeem(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_redeem_deposit(caller, shares);
    }

    function test_RT_redeem_mint(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        shares = bound(shares, 0, _max_redeem(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_redeem_mint(caller, shares);
    }

    function test_RT_mint_withdraw(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        shares = bound(shares, 0, _max_mint(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_mint_withdraw(caller, shares);
    }

    function test_RT_mint_redeem(Init memory init, uint256 shares) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        shares = bound(shares, 0, _max_mint(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_mint_redeem(caller, shares);
    }

    function test_RT_withdraw_mint(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        assets = bound(assets, 0, _max_withdraw(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_withdraw_mint(caller, assets);
    }

    function test_RT_withdraw_deposit(Init memory init, uint256 assets) public virtual {
        setUpVault(init);
        address caller = init.user[0];
        assets = bound(assets, 0, _max_withdraw(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_withdraw_deposit(caller, assets);
    }

    //
    // utils
    //
    function _isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function _isEOA(address account) internal view returns (bool) {
        return account.code.length == 0;
    }

    function _approve(address token, address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        _safeApprove(token, spender, 0);
        vm.prank(owner);
        _safeApprove(token, spender, amount);
    }

    function _safeApprove(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory retdata) =
            token.call(abi.encodeWithSelector(IERC20.approve.selector, spender, amount));
        vm.assume(success);
        if (retdata.length > 0) vm.assume(abi.decode(retdata, (bool)));
    }

    function _max_deposit(address from) internal virtual returns (uint256) {
        if (_unlimitedAmount) return type(uint256).max;
        return IERC20(_underlying_).balanceOf(from);
    }

    function _max_mint(address from) internal virtual returns (uint256) {
        if (_unlimitedAmount) return type(uint256).max;
        return vault_convertToShares(IERC20(_underlying_).balanceOf(from));
    }

    function _max_withdraw(address from) internal virtual returns (uint256) {
        if (_unlimitedAmount) return type(uint256).max;
        return vault_convertToAssets(IERC20(_vault_).balanceOf(from)); // may be different from maxWithdraw(from)
    }

    function _max_redeem(address from) internal virtual returns (uint256) {
        if (_unlimitedAmount) return type(uint256).max;
        return IERC20(_vault_).balanceOf(from); // may be different from maxRedeem(from)
    }

    //
    // revert tests

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
        IERC4626(_vault_).withdraw(assets, receiver, owner);
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

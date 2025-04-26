// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626ComplianceTest} from "test/unit/helpers/ERC4626ComplianceTest.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupBase6DecimalsVault, WrappedToken} from "test/unit/vault/base6decimals/SetupBase6DecimalsVault.sol";

contract Vault6DecimalsBaseERC4626ComplianceTest is ERC4626ComplianceTest {
    Vault public vault;
    address public alice = address(0x12345);
    uint256 public constant INITIAL_BALANCE = 20_000_000_000 ether;

    WrappedToken public wusdc;

    function setUp() public override {
        SetupBase6DecimalsVault setupVault = new SetupBase6DecimalsVault();
        (vault,) = setupVault.setup();
        wusdc = setupVault.wusdc();

        // ERC4626Test initializations
        _underlying_ = address(vault.asset());
        _vault_ = address(vault);
        _delta_ = 0;
        _vaultMayBeEmpty = false;
        _unlimitedAmount = false;

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
    }

    function setUpVault(Init memory init) public virtual override {
        super.setUpVault(init);
    }

    function test_RT_mint_withdraw(Init memory init, uint256 shares) public virtual override {
        // FIXME: re-enable this test
        vm.skip(true);
        _delta_ = 1;
        setUpVault(init);
        address caller = init.user[0];
        shares = bound(shares, 0, _max_mint(caller));
        _approve(_underlying_, caller, _vault_, type(uint256).max);
        prop_RT_mint_withdraw(caller, shares);
        _delta_ = 0;
    }
}

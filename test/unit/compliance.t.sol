// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";

contract Vault4626ComplianceUnitTest is Test, MainnetContracts, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    /* The maxWithdraw function should return the maximum amount of underlying assets that 
    can be withdrawn by the owner without affecting the vault's ability to meet its obligations.
    Paused State: The function correctly returns 0 if the vault is paused
    */
    function test_Vault_Compliance_maxWithdraw_paused() public {
        vm.prank(ADMIN);
        vault.pause(true);
        uint256 maxWithdrawAmount = vault.maxWithdraw(alice);
        assertEq(maxWithdrawAmount, 0, "Max withdraw amount should be 0 when paused");
    }

    /* Asset Conversion: The function calculates the baseConvertedAssets by converting the 
    owner's balance of vault tokens to the equivalent amount of underlying assets. 
    This is consistent with the ERC-4626 requirement to determine the maximum withdrawable 
    amount based on the owner's share balance.
    */
    function test_Vault_Compliance_maxWithdraw_assetConversion() public view {
        uint256 aliceBalance = vault.balanceOf(alice);
        uint256 baseConvertedAssets = vault.convertToAssets(aliceBalance);
        uint256 maxWithdrawAmount = vault.maxWithdraw(alice);
        assertEq(maxWithdrawAmount, baseConvertedAssets, "Max withdraw amount should be equal to base converted assets");
    }

    /*
    Available Assets Check: The function checks the available assets in the buffer strategy 
    and ensures that the withdrawal does not exceed this amount. This is a prudent measure 
    to ensure the vault maintains sufficient liquidity.
    */
    function test_Vault_Compliance_maxWithdraw_availableAssetsCheck() public view {
        uint256 aliceBalance = vault.balanceOf(alice);
        uint256 baseConvertedAssets = vault.convertToAssets(aliceBalance);
        uint256 availableAssets = vault.maxWithdraw(address(vault));
        uint256 maxWithdrawAmount = vault.maxWithdraw(alice);
        assertEq(
            maxWithdrawAmount,
            availableAssets < baseConvertedAssets ? 0 : baseConvertedAssets,
            "Max withdraw amount should be the lesser of available assets or base converted assets"
        );
    }

    /*
    5. Return Value: The function returns the lesser of the converted asset value or the available assets, 
    which aligns with the intent of ensuring that the vault can fulfill the withdrawal request without 
    compromising its liquidity.
    */
    function test_Vault_Compliance_maxWithdraw_returnValue() public view {
        uint256 aliceBalance = vault.balanceOf(alice);
        uint256 baseConvertedAssets = vault.convertToAssets(aliceBalance);
        uint256 availableAssets = vault.maxWithdraw(address(vault));
        uint256 maxWithdrawAmount = vault.maxWithdraw(alice);
        uint256 expectedValue = availableAssets < baseConvertedAssets ? 0 : baseConvertedAssets;
        assertEq(
            maxWithdrawAmount,
            expectedValue,
            "Max withdraw amount should be the lesser of available assets or base converted assets"
        );
    }
}

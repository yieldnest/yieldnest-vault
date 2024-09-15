// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SingleVault} from "src/SingleVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Math} from "src/Common.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {LocalActors} from "script/Actors.sol";

import "forge-std/Test.sol";

contract SingleInvariantTests is Test, LocalActors, TestConstants {
    using Math for uint256;

    SingleVault public vault;
    MockERC20 public asset;
    address public USER = address(33);

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = MockERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));

        Etches etches = new Etches();
        etches.mockListaStakeManager();

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault(asset);
    }

    event Log(uint256 amount, string name);

    function test_totalAssetsAlwaysCorrect(uint256 depositAmount) public {
        if (depositAmount < 1) return;
        if (depositAmount > 1e50) return;

        uint256 initialTotalAssets = vault.totalAssets();
        depositHelper(USER, depositAmount);
        uint256 currentTotalAssets = vault.totalAssets();
        uint256 expectedDepositAssets = vault.previewDeposit(depositAmount);
        uint256 expectedAssets = initialTotalAssets + expectedDepositAssets;
        assertClose(currentTotalAssets, expectedAssets, 10, "Total assets mismatch after deposit");
    }

    function test_totalSupplyAlwaysCorrect(uint256 depositAmount) public {
        if (depositAmount < 1) return;
        if (depositAmount > 1e50) return;

        uint256 initialTotalSupply = vault.totalSupply();
        depositHelper(USER, depositAmount);
        uint256 currentTotalSupply = vault.totalSupply();
        uint256 expectedDepositAssets = vault.previewDeposit(depositAmount);
        uint256 expectedSupply = initialTotalSupply + expectedDepositAssets;
        assertClose(currentTotalSupply, expectedSupply, 1, "Total supply mismatch after deposit");
    }

    function test_totalSupplyMatchesBalances(uint256 depositAmount) public {
        if (depositAmount < 2) return;
        if (depositAmount > 1e50) return;

        depositHelper(USER, depositAmount);
        uint256 total = vault.totalSupply();
        assertEq(vault.convertToShares(depositAmount + 1 ether), total, "Total supply does not balances");
    }

    function test_conversionConsistency(uint256 depositAmount) public view {
        if (depositAmount < 2) return;
        if (depositAmount > 1e50) return;
        uint256 shares = vault.convertToShares(depositAmount);
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertClose(depositAmount, convertedAssets, 1, "Conversion inconsistency");
    }

    function depositHelper(address user, uint256 depositAmount) public {
        vm.startPrank(user);
        asset.mint(depositAmount);
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));
        vm.stopPrank();
    }

    function assertClose(uint256 actual, uint256 expected, uint256 delta, string memory message) internal pure {
        require(actual >= expected - delta && actual <= expected + delta, message);
    }
}

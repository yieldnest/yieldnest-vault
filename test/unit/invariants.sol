// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {SingleVault} from "src/SingleVault.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {Math, IERC20} from "src/Common.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract SingleInvariantTests is Test, SetupHelper, MainnetActors {
    using Math for uint256;

    SingleVault public vault;
    address public USER = address(33);

    WETH9 public asset;

    function setUp() public {
        asset = WETH9(payable(MainnetContracts.WETH));
        vault = createVault();
    }

    event Log(uint256 amount, string name);

    function test_Vault_totalAssetsAlwaysCorrect(uint256 depositAmount) public {
        if (depositAmount < 1) return;
        if (depositAmount > 1e50) return;

        uint256 initialTotalAssets = vault.totalAssets();
        depositHelper(USER, depositAmount);
        uint256 currentTotalAssets = vault.totalAssets();
        uint256 expectedDepositAssets = vault.previewDeposit(depositAmount);
        uint256 expectedAssets = initialTotalAssets + expectedDepositAssets;
        assertClose(currentTotalAssets, expectedAssets, 10, "Total assets mismatch after deposit");
    }

    function test_Vault_totalSupplyAlwaysCorrect(uint256 depositAmount) public {
        if (depositAmount < 1) return;
        if (depositAmount > 1e50) return;

        uint256 initialTotalSupply = vault.totalSupply();
        depositHelper(USER, depositAmount);
        uint256 currentTotalSupply = vault.totalSupply();
        uint256 expectedDepositAssets = vault.previewDeposit(depositAmount);
        uint256 expectedSupply = initialTotalSupply + expectedDepositAssets;
        assertClose(currentTotalSupply, expectedSupply, 1, "Total supply mismatch after deposit");
    }

    function test_Vault_totalSupplyMatchesBalances(uint256 depositAmount) public {
        if (depositAmount < 2) return;
        if (depositAmount > 1e50) return;

        depositHelper(USER, depositAmount);
        uint256 total = vault.totalSupply();
        assertEq(vault.convertToShares(depositAmount + 1 ether), total, "Total supply does not balances");
    }

    function test_Vault_conversionConsistency(uint256 depositAmount) public view {
        if (depositAmount < 2) return;
        if (depositAmount > 1e50) return;
        uint256 shares = vault.convertToShares(depositAmount);
        uint256 convertedAssets = vault.convertToAssets(shares);
        assertClose(depositAmount, convertedAssets, 1, "Conversion inconsistency");
    }

    function depositHelper(address user, uint256 depositAmount) public {
        vm.startPrank(user);
        deal(user, depositAmount);
        asset.deposit{value: depositAmount}();
        IERC20(address(asset)).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, address(this));
        vm.stopPrank();
    }

    function assertClose(uint256 actual, uint256 expected, uint256 delta, string memory message) internal pure {
        require(actual >= expected - delta && actual <= expected + delta, message);
    }
}

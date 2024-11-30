// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {TestPlugin} from "test/unit/helpers/TestPlugin.sol";
import {IERC20} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IProvider, IChainlinkAggregator} from "src/interface/IProvider.sol";
import {console} from "lib/forge-std/src/console.sol";

contract VaultAccountingUnitTest is Test, AssertUtils, MainnetActors, Etches {
    Vault public vaultImplementation;

    Vault public vault;
    WETH9 public weth;
    TestPlugin public plugin;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth, plugin) = setupVault.setup();

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = address(plugin);
        targets[1] = address(plugin);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approveToken(address,address,uint256)", MC.WETH, vault.buffer(), amount);
        data[1] =
            abi.encodeWithSignature("depositIntoVault(address,uint256,address)", MC.BUFFER, amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);
    }

    function test_Vault_Accounting_convertToShares() public view {
        uint256 assets = 1000 ether;
        uint256 shares = vault.convertToShares(assets);
        assertEq(shares, vault.previewDeposit(assets), "Shares should match previewDeposit");
    }

    function test_Vault_Accounting_convertToAssets() public view {
        uint256 shares = 1000 ether;
        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, vault.previewRedeem(shares), "Assets should match previewRedeem");
    }

    function test_Vault_Accounting_totalAssets_afterDeposit() public {
        uint256 depositAmount = 1000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount, "Total assets should match the deposit amount");
    }

    function test_Vault_Accounting_totalAssets_afterMultipleDeposits() public {
        uint256 depositAmount1 = 1000 ether;
        uint256 depositAmount2 = 2000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount1, alice);
        vm.prank(alice);
        vault.deposit(depositAmount2, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(totalAssets, depositAmount1 + depositAmount2, "Total assets should match the sum of deposit amounts");
    }

    function test_Vault_Accounting_totalAssets_afterWithdraw() public {
        uint256 depositAmount = 1000 ether;
        uint256 withdrawAmount = 500 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(
            totalAssets,
            depositAmount - withdrawAmount,
            "Total assets should match the remaining amount after withdrawal"
        );
    }

    function test_Vault_Accounting_totalAssets_afterMultipleWithdrawals() public {
        uint256 depositAmount = 3000 ether;
        uint256 withdrawAmount1 = 1000 ether;
        uint256 withdrawAmount2 = 500 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount);

        vm.prank(alice);
        vault.withdraw(withdrawAmount1, alice, alice);
        vm.prank(alice);
        vault.withdraw(withdrawAmount2, alice, alice);
        uint256 totalAssets = vault.totalAssets();
        assertEq(
            totalAssets,
            depositAmount - withdrawAmount1 - withdrawAmount2,
            "Total assets should match the remaining amount after multiple withdrawals"
        );
    }

    function test_Vault_Accounting_totalSupply_afterDeposit() public {
        uint256 depositAmount = 1000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, depositAmount, "Total supply should match the deposit amount");
    }

    function test_Vault_Accounting_totalSupply_afterMultipleDeposits() public {
        uint256 depositAmount1 = 1000 ether;
        uint256 depositAmount2 = 2000 ether;
        vm.prank(alice);
        vault.deposit(depositAmount1, alice);
        vm.prank(alice);
        vault.deposit(depositAmount2, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(totalSupply, depositAmount1 + depositAmount2, "Total supply should match the sum of deposit amounts");
    }

    function test_Vault_Accounting_totalSupply_afterWithdraw() public {
        uint256 depositAmount = 1000 ether;
        uint256 bufferRatio = 5;

        vm.startPrank(alice);
        weth.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        allocateToBuffer(depositAmount / bufferRatio);

        vm.startPrank(alice);
        uint256 maxWithdraw = vault.maxWithdraw(alice);
        vault.withdraw(maxWithdraw, alice, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(
            totalSupply, depositAmount - maxWithdraw, "Total supply should match the remaining amount after withdrawal"
        );
        vm.stopPrank();
    }

    function test_Vault_Accounting_totalSupply_afterMultipleWithdrawals() public {
        uint256 depositAmount = 3000 ether;
        uint256 bufferRatio = 5;

        uint256 withdrawAmount1 = vault.maxWithdraw(alice) / 3;
        uint256 withdrawAmount2 = vault.maxWithdraw(alice) / 7;

        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount / bufferRatio);

        vm.prank(alice);
        vault.withdraw(withdrawAmount1, alice, alice);
        vm.prank(alice);
        vault.withdraw(withdrawAmount2, alice, alice);
        uint256 totalSupply = vault.totalSupply();
        assertEq(
            totalSupply,
            depositAmount - withdrawAmount1 - withdrawAmount2,
            "Total supply should match the remaining amount after multiple withdrawals"
        );
    }

    function test_Vault_convertToAssets_multipleDepositsAndTransfers(uint256 rand) public {
        if (rand < 1 || rand > 10_000 ether) return;
        uint256 depositAmountWETH = rand;
        uint256 depositAmountSTETH = rand;

        bool success = false;
        uint256 expectedTotalAssets = 0;
        uint256 expectedTotalSupply = 0;

        console.log("expectedTotalAssets:", expectedTotalAssets);
        console.log("expectedTotalSupply:", expectedTotalSupply);

        address steth = MC.STETH;

        // Approve and deposit WETH : 1000 ether
        vm.startPrank(alice);
        weth.approve(address(vault), depositAmountWETH);
        uint256 shares = vault.deposit(depositAmountWETH, alice);
        expectedTotalAssets += depositAmountWETH;
        expectedTotalSupply += shares;
        vm.stopPrank();

        console.log("expectedTotalAssets:", expectedTotalAssets);
        console.log("expectedTotalSupply:", expectedTotalSupply);

        // Approve and deposit STETH :
        vm.startPrank(alice);
        deal(alice, depositAmountSTETH);
        (success,) = MC.STETH.call{value: depositAmountSTETH}("");
        require(success, "Steth transfer failed");
        uint256 aliceStEthDepositAmount = IERC20(steth).balanceOf(alice);

        IERC20(steth).approve(address(vault), aliceStEthDepositAmount);
        shares = vault.depositAsset(steth, aliceStEthDepositAmount, alice);
        expectedTotalAssets += vault.previewRedeem(shares);
        expectedTotalSupply += shares;

        console.log("expectedTotalAssets:", expectedTotalAssets);
        console.log("expectedTotalSupply:", expectedTotalSupply);

        // Direct transfer of WETH to the vault
        deal(alice, depositAmountWETH);
        (success,) = MC.WETH.call{value: depositAmountWETH}("");
        require(success, "Weth transfer failed");
        IERC20(MC.WETH).transfer(address(vault), depositAmountWETH);
        expectedTotalAssets += depositAmountWETH;

        // Direct transfer of STETH to the vault
        deal(alice, depositAmountSTETH);
        (success,) = MC.STETH.call{value: depositAmountSTETH}("");
        require(success, "Steth transfer failed");
        aliceStEthDepositAmount = IERC20(steth).balanceOf(alice);

        uint256 rate = IProvider(MC.PROVIDER).getRate(MC.STETH);
        expectedTotalAssets += (aliceStEthDepositAmount * rate) / (10 ** 18);

        IERC20(steth).transfer(address(vault), aliceStEthDepositAmount);

        vault.processAccounting();

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();

        assertEqThreshold(totalAssets, expectedTotalAssets, 5000, "totalAssets should be expectedAssets");
        assertEqThreshold(totalSupply, expectedTotalSupply, 5000, "totalSupply should be expectedSupply");
    }
}

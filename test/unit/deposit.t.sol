// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {ETHRateProvider, IERC20, TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";

contract Vault_Deposit_Unit_Test is Test, MainnetContracts, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    ETHRateProvider public rateProvider;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;

    function setUp() public {
        weth = WETH9(payable(WETH));
        vaultImplementation = new Vault();
        rateProvider = new ETHRateProvider();

        // etch to mock the mainnet contracts address
        mockWETH9();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, address(this), "Vault Token", "VTK");

        vaultProxy = new TransparentUpgradeableProxy(address(vaultImplementation), address(this), initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(address(vaultProxy));

        // Set up the rate provider
        vault.setRateProvider(address(rateProvider));

        // Add WETH as an asset
        vault.addAsset(address(weth), 18);

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);

        // Unpause the vault
        vault.pause(false);
    }

    function testDeposit() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // Check that shares were minted
        assertGt(sharesMinted, 0, "No shares were minted");

        // Check that the vault received the tokens
        assertEq(weth.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(weth.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly");

        // Check that Alice received the correct amount of shares
        assertEq(vault.balanceOf(alice), sharesMinted, "Alice did not receive the correct amount of shares");

        // Check that total assets increased
        assertEq(vault.totalAssets(), depositAmount, "Total assets did not increase correctly");
    }

    function testDepositZeroAmount() public {
        vm.prank(alice);
        uint256 sharesMinted = vault.deposit(0, alice);

        assertEq(sharesMinted, 0, "Shares were minted for zero deposit");
    }

    function testDepositExceedsBalance() public {
        uint256 excessiveAmount = INITIAL_BALANCE + 1;

        vm.prank(alice);
        vm.expectRevert(); // Expect the transaction to revert
        vault.deposit(excessiveAmount, alice);
    }
}

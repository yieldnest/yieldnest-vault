// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Vault} from "src/Vault.sol";
import {ETHRateProvider, ProxyAdmin, TransparentUpgradeableProxy, IVault} from "src/Common.sol";
import {MockWETH} from "test/mocks/MockWETH.sol";

contract Vault_Deposit_Unit_Test is Test {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    ProxyAdmin public proxyAdmin;
    MockWETH public mockWETH;
    ETHRateProvider public rateProvider;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 1000 * 10 ** 18;

    function setUp() public {
        mockWETH = new MockWETH();
        vaultImplementation = new Vault();
        proxyAdmin = new ProxyAdmin();
        rateProvider = new ETHRateProvider();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, address(this), "Vault Token", "VTK");

        vaultProxy = new TransparentUpgradeableProxy(address(vaultImplementation), address(proxyAdmin), initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(address(vaultProxy));

        // Set up the rate provider
        vault.setRateProvider(address(rateProvider));

        // Add WETH as an asset
        vault.addAsset(address(mockWETH), 18);

        // Give Alice some tokens
        mockWETH.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        mockWETH.approve(address(vault), type(uint256).max);

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
        assertEq(mockWETH.balanceOf(address(vault)), depositAmount, "Vault did not receive tokens");

        // Check that Alice's token balance decreased
        assertEq(
            mockWETH.balanceOf(alice), INITIAL_BALANCE - depositAmount, "Alice's balance did not decrease correctly"
        );

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

    function testUpgrade() public {
        // Deploy a new implementation
        Vault newImplementation = new Vault();

        // Upgrade the proxy to the new implementation
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(vaultProxy))), address(newImplementation));

        // Verify the upgrade
        assertEq(
            proxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(vaultProxy)))),
            address(newImplementation),
            "Upgrade failed"
        );
    }
}

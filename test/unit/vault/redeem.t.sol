// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy, IERC20, Math} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {FeeHooks} from "src/hooks/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IVault} from "src/interface/IVault.sol";

contract VaultRedeemUnitTest is Test, MainnetActors, Etches, AssertUtils {
    using Math for uint256;

    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public chad = address(0x3);

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

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = MC.BUFFER;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function test_Vault_previewRedeem(uint256 shares, bool alwaysComputeTotalAssets) external {
        if (shares < 2) return;
        if (shares > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 assets = vault.previewWithdraw(shares);
        assertEq(assets, shares, "Preview Assets response not shares");
    }

    function test_Vault_redeem_success(uint256 amount, bool alwaysComputeTotalAssets) external {
        if (amount < 2) return;
        if (amount > 100_000 ether) return;

        vm.prank(ASSET_MANAGER);
        vault.setAlwaysComputeTotalAssets(alwaysComputeTotalAssets);

        uint256 aliceWethBalanceBefore = weth.balanceOf(alice);
        vm.prank(alice);
        uint256 depositShares = vault.deposit(amount, alice);

        allocateToBuffer(amount);

        uint256 balanceBefore = weth.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 previewAssets = vault.previewRedeem(depositShares);

        vm.prank(alice);
        uint256 assetsAfter = vault.redeem(depositShares, alice, alice);
        uint256 balanceAfter = weth.balanceOf(alice);
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 aliceWethBalanceAfter = weth.balanceOf(alice);

        assertEq(assetsAfter, previewAssets, "assetsAfter = previewAmount");
        assertEq(balanceAfter, balanceBefore + previewAssets, "balanceAfter = balanceBefore + previewAmount");

        assertEq(
            totalAssetsBefore, totalAssetsAfter + previewAssets, "totalAssetsBefore = totalAssetsAfter + previewAmount"
        );
        assertEq(
            aliceWethBalanceBefore,
            aliceWethBalanceAfter,
            "Alice's WETH balance should be increased by the assets withdrawn"
        );
    }

    function test_Vault_redeemMoreThanShareBalance() public {
        vm.startPrank(alice);
        uint256 depositAmount = 100 ether;
        uint256 sharesMinted = vault.deposit(depositAmount, alice);

        // Attempt to redeem more shares than the balance
        uint256 excessiveRedeemAmount = sharesMinted + 1;
        vm.expectRevert();
        vault.redeem(excessiveRedeemAmount, alice, alice);
    }

    function test_Vault_redeemWhilePaused() public {
        vm.prank(PAUSER);
        vault.pause();
        assertEq(vault.paused(), true);

        vm.prank(alice);
        vm.expectRevert();
        vault.redeem(1000, alice, alice);
    }

    function test_Vault_maxRedeem() public view {
        uint256 maxRedeem = vault.maxRedeem(alice);
        assertEq(maxRedeem, 0, "Max redeem does not match");
    }

    function test_Vault_maxRedeem_afterDeposit() public {
        // Simulate a deposit
        uint256 depositAmount = 1000;
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        allocateToBuffer(depositAmount);
        // Test maxRedeem after deposit
        uint256 maxRedeemAfterDeposit = vault.maxRedeem(alice);
        assertEq(maxRedeemAfterDeposit, depositAmount, "Max redeem after deposit does not match");
    }
}

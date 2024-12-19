// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {TransparentUpgradeableProxy, IERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {console} from "lib/forge-std/src/console.sol";

contract VaultWithdrawFeesUnitTest is Test, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;

    address public alice = address(0x1);
    address public bob = address(0x2);
    address public chad = address(0x3);

    uint256 public constant INITIAL_BALANCE = 100_000 ether;
    uint256 public bufferRatio = 10_000_000;

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

        // Set base withdrawal fee to 0.1% (0.1% * 1e8)
        vm.prank(ADMIN);
        vault.setBaseWithdrawalFee(100_000);
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

        vm.prank(ADMIN);
        vault.processor(targets, values, data);
    }

    function test_Vault_previewRedeemWithFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawnShares = vault.convertToShares(withdrawnAssets);

        uint256 redeemedPreview = vault.previewRedeem(withdrawnShares);
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqRel(
            redeemedPreview, withdrawnAssets - expectedFee, 1e14, "Withdrawal fee should be 0.1% of assets"
        );
    }

    function test_Vault_previewWithdrawWithFees(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawPreview = vault.previewWithdraw(withdrawnAssets);
        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.convertToShares(withdrawnAssets + expectedFee);
        assertApproxEqAbs(withdrawPreview, expectedShares, 1, "Preview withdraw shares should match expected");
    }

    function test_Vault_redeemWithFees(uint256 assets, uint256 withdrawnAssets) external {
        // Bound inputs to valid ranges
        vm.assume(assets >= 100000 && assets <= 100_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 100000);

        vm.prank(alice);
        vault.deposit(assets, alice);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        uint256 withdrawnShares = vault.convertToShares(withdrawnAssets);

        vm.prank(alice);
        uint256 redeemedAmount = vault.redeem(withdrawnShares, alice, alice);
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqRel(
            redeemedAmount, withdrawnAssets - expectedFee, 1e14, "Withdrawal fee should be 0.1% of assets"
        );
    }

    function test_Vault_withdrawWithFees(uint256 assets, uint256 withdrawnAssets) external {
        vm.assume(assets >= 100000 && assets <= 10_000 ether);
        vm.assume(withdrawnAssets <= assets);
        vm.assume(withdrawnAssets > 0);

        vm.prank(alice);
        vault.deposit(assets, alice);

        vm.prank(ADMIN);
        allocateToBuffer(assets);

        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        uint256 expectedShares = vault.convertToShares(withdrawnAssets + expectedFee);

        vm.prank(alice);
        uint256 withdrawAmount = vault.withdraw(withdrawnAssets, alice, alice);

        assertApproxEqAbs(withdrawAmount, expectedShares, 2, "Preview withdraw shares should match expected");
    }

    function test_Vault_feeOnRaw_FlatFee(uint256 assets) external {
        if (assets < 10) return;
        if (assets > 100_000 ether) return;

        vm.prank(alice);
        vault.deposit(assets, alice);

        uint256 maxBufferAssets = (assets * bufferRatio) / 1e8;
        vm.prank(ADMIN);
        allocateToBuffer(maxBufferAssets);

        uint256 withdrawnAssets = maxBufferAssets / 2;

        uint256 fee = vault._feeOnRaw(withdrawnAssets);

        // Base withdrawal fee is 0.1% (100_000)
        // Buffer flat fee ratio is 80% (80_000_000)
        // Vault buffer fraction is 10% (10_000_000)
        uint256 expectedFee = (withdrawnAssets * vault.baseWithdrawalFee()) / FeeMath.BASIS_POINT_SCALE;
        assertApproxEqAbs(fee, expectedFee, 1, "Fee should be 0.1% of assets");
    }

    function skiptest_Vault_withdraw_success(uint256 assets) external {
        if (assets < 2) return;
        if (assets > 100_000 ether) return;

        vm.prank(alice);
        uint256 depositShares = vault.deposit(assets, alice);

        allocateToBuffer(assets);
        uint256 previewAmount = vault.previewWithdraw(assets);

        uint256 aliceBalanceBefore = vault.balanceOf(alice);
        uint256 totalAssetsBefore = vault.totalAssets();

        vm.prank(alice);
        uint256 shares = vault.withdraw(assets, alice, alice);
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 aliceBalanceAfter = vault.balanceOf(alice);

        assertEq(aliceBalanceBefore, aliceBalanceAfter + shares, "Alice's balance should be less the shares withdrawn");
        assertEq(previewAmount, shares, "Preview withdraw amount not preview amount");
        assertEq(depositShares, shares, "Deposit shares not match with withdraw shares");
        assertLt(totalAssetsAfter, totalAssetsBefore, "Total assets should be less after withdraw");
        assertEq(
            totalAssetsBefore,
            totalAssetsAfter + assets,
            "Total assets should be total assets after plus assets withdrawn"
        );
    }
}

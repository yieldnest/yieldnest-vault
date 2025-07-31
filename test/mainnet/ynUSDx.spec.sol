// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISuperUSDC} from "src/interface/ISuperUSDC.sol";
import {BaseVault} from "src/BaseVault.sol";
import {FeeMath} from "src/module/FeeMath.sol";
import {IVault} from "src/interface/IVault.sol";

contract YnUSDxTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        bufferStrategy = vault.buffer();
        vm.stopPrank();
    }

    function test_Vault_ERC20_view_functions() public view {
        assertEq(vault.name(), "ynUSD Max", "Vault name should be 'ynUSD Max'");

        assertEq(vault.symbol(), "ynUSDx", "Vault symbol should be 'ynUSDx'");

        assertEq(vault.decimals(), 18, "Vault decimals should be 18");
    }

    function test_Vault_ERC4626_view_functions() public view {
        assertEq(address(vault.asset()), MC.USDC, "Vault asset should be USDC");

        uint256 totalAssets = vault.totalAssets();
        uint256 totalSupply = vault.totalSupply();
        assertGt(totalAssets, 0, "TotalAssets should be greater than 0");
        assertGt(totalSupply, 0, "TotalSupply should be greater than 0");

        uint256 amount = 1e6;
        uint256 shares = vault.convertToShares(amount);

        uint256 convertedAssets = vault.convertToAssets(shares);
        assertApproxEqAbs(convertedAssets, amount, 10, "Converted assets should be equal to amount deposited");

        uint256 maxDeposit = vault.maxDeposit(address(this));
        assertGt(maxDeposit, 0, "Max deposit should be greater than 0");

        uint256 maxMint = vault.maxMint(address(this));
        assertGt(maxMint, 0, "Max mint should be greater than 0");

        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        assertEq(maxWithdraw, 0, "Max withdraw should be zero");

        uint256 maxRedeem = vault.maxRedeem(address(this));
        assertEq(maxRedeem, 0, "Max redeem should be zero");
    }

    function test_max_vault_view_functions() public view {
        assertFalse(vault.paused(), "Vault should not be paused");

        address[] memory assets = vault.getAssets();
        assertEq(assets.length, 17, "There should be 14 assets in the vault");
        assertEq(assets[0], address(wrappedUSDC), "First asset should be wrappedUSDC");
        assertEq(assets[1], MC.USDC, "Second asset should be USDC");

        assertEq(vault.asset(), MC.USDC, "Vault asset should be USDC");
        assertEq(vault.defaultAssetIndex(), 1, "Default asset index should be 1");
    }

    function test_WithdrawalFee(uint256 initialDepositAmount, uint256 donationAmount, uint64 withdrawalFee) public {
        initialDepositAmount = bound(initialDepositAmount, 1000, 1_000_000e6);
        donationAmount = bound(donationAmount, 1000, 1_000_000e6);
        withdrawalFee = uint64(bound(withdrawalFee, 1, 1e6));

        vm.startPrank(ADMIN);
        vault.setBaseWithdrawalFee(withdrawalFee);
        vm.stopPrank();

        address alice = makeAddr("alice");
        address donator = makeAddr("donator");

        uint256 initialUSDCBalanceOfVault = IERC20(MC.USDC).balanceOf(address(vault));

        vm.startPrank(alice);
        deal(MC.USDC, alice, initialDepositAmount);
        IERC20(MC.USDC).approve(address(vault), initialDepositAmount);
        uint256 shares = vault.deposit(initialDepositAmount, alice);
        vm.stopPrank();

        vm.startPrank(donator);
        deal(MC.USDC, donator, donationAmount);
        IERC20(MC.USDC).transfer(address(vault), donationAmount);
        vault.processAccounting();
        vm.stopPrank();

        allocateToBuffer(initialDepositAmount + donationAmount);

        uint256 expectedRedemption = vault.previewRedeem(shares);
        uint256 fees = FeeMath.feeOnTotal(initialDepositAmount + donationAmount, withdrawalFee);

        vm.startPrank(alice);
        uint256 usdcBalanceOfAliceBefore = IERC20(MC.USDC).balanceOf(alice);
        vault.redeem(shares, alice, alice);
        uint256 usdcBalanceOfAliceAfter = IERC20(MC.USDC).balanceOf(alice);
        vm.stopPrank();

        uint256 actualUSDCReceivedByAlice = usdcBalanceOfAliceAfter - usdcBalanceOfAliceBefore;

        assertApproxEqAbs(
            actualUSDCReceivedByAlice, expectedRedemption, 1e2, "User should receive amount minus withdrawal fee"
        );
        assertEq(vault.balanceOf(alice), 0, "User should have no shares left");
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            initialUSDCBalanceOfVault,
            "Vault's USDC balance should be the same as before the withdrawal"
        );
        assertGt(fees, 0, "Withdrawal fee should be greater than 0");
    }

    function test_Vault_withdrawUSDC_afterUSDEDeposit(
        uint256 usdcDepositAmount,
        uint256 usdeDepositAmount,
        uint256 usdcWithdrawAmount
    ) public {
        usdcDepositAmount = bound(usdcDepositAmount, 1001, 1_000_000e6); // 6 decimals
        usdeDepositAmount = bound(usdeDepositAmount, 1001, 1_000_000e18); // 18 decimals
        usdcWithdrawAmount = bound(usdcWithdrawAmount, 1, usdcDepositAmount / 2); // 6 decimals

        address alice = makeAddr("alice");

        // Give Alice USDC
        deal(MC.USDC, alice, usdcDepositAmount);
        uint256 initialUSDCBalanceOfVault = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 initialBaseAssetsOfVault = vault.totalBaseAssets();
        uint256 initialTotalAssetsOfVault = vault.totalAssets();

        // Approve vault to spend Alice's USDC
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), type(uint256).max);

        // Deposit USDC using depositAsset
        uint256 sharesMintedFromUSDC = vault.depositAsset(MC.USDC, usdcDepositAmount, alice);
        vm.stopPrank();

        // Check that the vault received the USDC
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            usdcDepositAmount + initialUSDCBalanceOfVault,
            "Vault did not receive USDC"
        );

        allocateToBuffer(usdcDepositAmount);

        vm.startPrank(TIMELOCK);
        // mark USDE as active
        IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
        vault.updateAsset(6, fields);
        vm.stopPrank();

        // Give Alice USDE
        deal(MC.USDE, alice, usdeDepositAmount);

        // Approve vault to spend Alice's USDE
        vm.startPrank(alice);
        IERC20(MC.USDE).approve(address(vault), type(uint256).max);

        // Deposit USDE using depositAsset
        uint256 sharesMintedFromUSDE = vault.depositAsset(MC.USDE, usdeDepositAmount, alice);
        vm.stopPrank();

        vault.processAccounting();

        // Check that the vault received the USDE
        assertEq(IERC20(MC.USDE).balanceOf(address(vault)), usdeDepositAmount, "Vault did not receive USDE");
        {
            // Withdraw USDC using withdrawAsset
            vm.startPrank(alice);
            uint256 sharesToBurn = vault.previewWithdraw(usdcWithdrawAmount);
            uint256 maxRedeem = vault.maxRedeem(alice);
            sharesToBurn = maxRedeem < sharesToBurn ? maxRedeem : sharesToBurn;
            uint256 assetsWithdrawn = vault.redeem(sharesToBurn, alice, alice);
            vm.stopPrank();

            // Check that Alice's USDC balance increased
            assertEq(
                IERC20(MC.USDC).balanceOf(alice), assetsWithdrawn, "Alice's USDC balance did not increase correctly"
            );
            assertApproxEqAbs(assetsWithdrawn, usdcWithdrawAmount, 1e6, "Alice should receive USDC deposit amount");

            // Check that all shares from USDC deposit were burned
            assertEq(
                vault.balanceOf(alice),
                sharesMintedFromUSDE + sharesMintedFromUSDC - sharesToBurn,
                "Alice's shares from USDC were not burned correctly"
            );
        }

        // Check that total assets decreased by the USD value of USDC
        assertApproxEqAbs(
            vault.totalAssets(),
            usdeDepositAmount / 1e12 + usdcDepositAmount - usdcWithdrawAmount + initialTotalAssetsOfVault,
            1e6,
            "Total assets did not decrease correctly"
        );
        // Check that the total base assets in the vault match the expected value
        assertApproxEqAbs(
            vault.totalBaseAssets(),
            usdeDepositAmount + (usdcDepositAmount - usdcWithdrawAmount) * 1e12 + initialBaseAssetsOfVault,
            1e18,
            "Total base assets did not match expected value after withdrawal"
        );
    }

    function allocateToBuffer(uint256 depositAmount) public returns (uint256 bufferStrategySharesMinted) {
        // Allocate to buffer (MorphoGauntletUSDC core vault)
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = MC.USDC;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(bufferStrategy), depositAmount));

            targets[1] = address(bufferStrategy);
            values[1] = 0;
            data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();

            bufferStrategySharesMinted = abi.decode(returnData[1], (uint256));
        }
        vault.processAccounting();
    }
}

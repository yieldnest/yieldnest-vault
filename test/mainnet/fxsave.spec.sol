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
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

contract FXSaveTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        vm.stopPrank();
        bufferStrategy = MC.MORPHO_GAUNTLET_USDC_VAULT;
    }

    function convertToUSDC(uint256 shares) public view returns (uint256) {
        IFxUSDBasePool fxBase = IFxUSDBasePool(MC.FXBASE);

        (uint256 yieldTokenAmount, uint256 fxStableAmount) = fxBase.previewRedeem(shares);
        return yieldTokenAmount + fxStableAmount * 1e12;
    }

    function depositToFxBase(uint256 depositAmount) internal {
        ProcessorUtils.depositToFxBase(address(vault), depositAmount, PROCESSOR);
    }

    function depositToFxSave() internal {
        // 2. Allocate to fxSAVE using processor
        // Prepare calldata for IERC4626.deposit(uint256 assets, address receiver)
        uint256 fxBaseShares = IERC20(MC.FXBASE).balanceOf(address(vault));
        require(fxBaseShares > 0, "Vault should have fxBASE shares to allocate");

        bytes memory fxSaveDepositCalldata =
            abi.encodeWithSelector(IERC4626(MC.FXSAVE).deposit.selector, fxBaseShares, address(vault));

        // Approve FXSAVE to spend fxBASE shares via processor
        address[] memory targets2 = new address[](2);
        uint256[] memory values2 = new uint256[](2);
        bytes[] memory calldatas2 = new bytes[](2);

        // 1. Approve FXSAVE to spend fxBASE from the vault
        targets2[0] = MC.FXBASE;
        values2[0] = 0;
        calldatas2[0] = abi.encodeWithSelector(IERC20(MC.FXBASE).approve.selector, MC.FXSAVE, fxBaseShares);

        // 2. Call FXSAVE.deposit
        targets2[1] = MC.FXSAVE;
        values2[1] = 0;
        calldatas2[1] = fxSaveDepositCalldata;

        vm.startPrank(PROCESSOR);
        vault.processor(targets2, values2, calldatas2);
        vm.stopPrank();

        // Check that vault's fxBASE balance is now 0 (all allocated)
        assertEq(IERC20(MC.FXBASE).balanceOf(address(vault)), 0, "Vault fxBASE should be 0 after allocation to fxSAVE");

        // Check that vault now has FXSAVE shares
        uint256 fxSaveShares = IERC20(MC.FXSAVE).balanceOf(address(vault));
        assertGt(fxSaveShares, 0, "Vault should have received FXSAVE shares");

        vault.processAccounting();
    }

    function requestRedeemForFxBase(uint256 fxBaseShares) internal {
        // Prepare calldata for Withdrawer.requestRedeem(uint256 shares)
        bytes memory withdrawerRequestRedeemCalldata =
            abi.encodeWithSelector(IFxUSDBasePool.requestRedeem.selector, fxBaseShares);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        // 1. Call Withdrawer.requestRedeem
        targets[0] = MC.FXBASE;
        values[0] = 0;
        calldatas[0] = withdrawerRequestRedeemCalldata;

        vm.startPrank(PROCESSOR);
        withdrawer.processor(targets, values, calldatas);
        vm.stopPrank();

        withdrawer.processAccounting();
        vault.processAccounting();
    }

    function redeemFromFxBase(uint256 fxBaseShares) internal {
        // Prepare calldata for Withdrawer.redeem(uint256 shares)
        bytes memory withdrawerRedeemCalldata =
            abi.encodeWithSelector(IFxUSDBasePool.redeem.selector, address(withdrawer), fxBaseShares);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        // 1. Call Withdrawer.redeem(address vault, uint256 shares)
        targets[0] = MC.FXBASE;
        values[0] = 0;
        calldatas[0] = withdrawerRedeemCalldata;

        vm.startPrank(PROCESSOR);
        withdrawer.processor(targets, values, calldatas);
        vm.stopPrank();

        withdrawer.processAccounting();
        vault.processAccounting();
    }

    function redeemFromFxSave(uint256 fxSaveShares) internal {
        require(fxSaveShares > 0, "Vault should have FXSAVE shares to redeem");

        // Prepare calldata for IERC4626.redeem(uint256 shares, address receiver, address owner)
        bytes memory fxSaveRedeemCalldata =
            abi.encodeWithSelector(IERC4626(MC.FXSAVE).redeem.selector, fxSaveShares, address(vault), address(vault));

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        // 1. Call FXSAVE.redeem
        targets[0] = MC.FXSAVE;
        values[0] = 0;
        calldatas[0] = fxSaveRedeemCalldata;

        vm.startPrank(PROCESSOR);
        vault.processor(targets, values, calldatas);
        vm.stopPrank();

        // Check that vault's FXSAVE balance is now 0 (all redeemed)
        assertEq(IERC20(MC.FXSAVE).balanceOf(address(vault)), 0, "Vault FXSAVE should be 0 after redeem");

        // Check that vault now has fxBASE shares
        uint256 fxBaseShares = IERC20(MC.FXBASE).balanceOf(address(vault));
        assertGt(fxBaseShares, 0, "Vault should have received fxBASE shares after redeem");

        vault.processAccounting();
    }

    function test_allocate_to_fxsave(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e6, 100e6);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        // Record vault's USDC balance and totalBaseAssets before deposit
        uint256 vaultUSDCBefore = IERC20(MC.USDC).balanceOf(address(vault));

        // Alice approves the vault to spend her USDC and deposits into the vault
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        uint256 shares = vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Record totalBaseAssets after deposit
        uint256 totalBaseAssetsAfterDeposit = vault.totalBaseAssets();

        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            vaultUSDCBefore + depositAmount,
            "Vault should have received USDC"
        );
        assertEq(vault.balanceOf(alice), shares, "Alice should have received vault shares");

        depositToFxBase(depositAmount);

        // Check that vault's USDC balance is now 0 (all allocated)
        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            vaultUSDCBefore,
            "Vault USDC should be 0 after allocation to fxBASE"
        );

        // Check that totalBaseAssets did not change after processor (allowing approx rel diff of 1e14)
        vm.assertApproxEqRel(
            totalBaseAssetsAfterDeposit,
            vault.totalBaseAssets(),
            2e14,
            "Vault totalBaseAssets should remain approx constant after fxBASE allocation"
        );

        depositToFxSave();

        // Check that totalBaseAssets did not change after processor (allowing approx rel diff of 1e14)
        vm.assertApproxEqRel(
            totalBaseAssetsAfterDeposit,
            vault.totalBaseAssets(),
            2e14,
            "Vault totalBaseAssets should remain approx constant after fxSAVE allocation"
        );
    }

    function test_redeem_fxsave(uint256 depositAmount) public {
        depositAmount = bound(depositAmount, 1e6, 10_000_000e6);

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount * 1e12);

        // Alice approves the vault to spend her USDC and deposits into the vault
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.deposit(depositAmount, alice);
        vm.stopPrank();

        // Record totalBaseAssets after deposit
        uint256 totalBaseAssetsAfterDeposit = vault.totalBaseAssets();

        // Assert after deposit
        assertEq(
            vault.totalBaseAssets(), totalBaseAssetsAfterDeposit, "totalBaseAssets should remain constant after deposit"
        );

        depositToFxBase(depositAmount);

        uint256 totalBaseAssetsAfterFxBaseAllocation = vault.totalBaseAssets();

        // Assert after depositToFxBase (allowing approx rel diff of 1e14)
        vm.assertApproxEqRel(
            vault.totalBaseAssets(),
            totalBaseAssetsAfterFxBaseAllocation,
            2e14,
            "Vault totalBaseAssets should remain approx constant after depositToFxBase"
        );

        // Measure fxSAVE balance before deposit
        uint256 fxSaveBalanceBefore = IERC20(MC.FXSAVE).balanceOf(address(vault));

        depositToFxSave();

        uint256 totalBaseAssetsAfterFxSaveAllocation = vault.totalBaseAssets();

        // Assert after depositToFxSave (allowing approx rel diff of 1e4)
        vm.assertApproxEqRel(
            totalBaseAssetsAfterFxSaveAllocation,
            totalBaseAssetsAfterFxBaseAllocation,
            1e4,
            "Vault totalBaseAssets should remain approx constant after depositToFxSave"
        );

        // Calculate the amount of fxSAVE obtained
        uint256 fxSaveObtained = IERC20(MC.FXSAVE).balanceOf(address(vault)) - fxSaveBalanceBefore;

        // Redeem all of fxSAVE obtained from the vault

        // Use only the fxSAVE obtained in this test
        require(fxSaveObtained > 0, "No fxSAVE obtained to redeem");

        // Measure fxBASE balance before redeem
        uint256 fxBaseBalanceBefore = IERC20(MC.FXBASE).balanceOf(address(vault));

        redeemFromFxSave(fxSaveObtained);

        // Assert after depositToFxSave (allowing approx rel diff of 1e4)
        vm.assertApproxEqRel(
            vault.totalBaseAssets(),
            totalBaseAssetsAfterFxSaveAllocation,
            1,
            "Vault totalBaseAssets should remain approx constant after depositToFxSave"
        );

        // Measure fxBASE balance after redeem
        uint256 fxBaseObtained = IERC20(MC.FXBASE).balanceOf(address(vault)) - fxBaseBalanceBefore;

        // Allocate fxBASE to the withdrawer contract instead of to FXSAVE
        ProcessorUtils.allocateToERC4626MAX(address(vault), MC.FXBASE, address(withdrawer), fxBaseObtained, PROCESSOR);

        withdrawer.processAccounting();
        vault.processAccounting();

        // Assert after allocateToERC4626MAX (allowing approx abs diff of 1 wei)
        vm.assertApproxEqAbs(
            vault.totalBaseAssets(),
            totalBaseAssetsAfterFxBaseAllocation,
            3,
            "totalBaseAssets should remain approx constant after allocateToERC4626MAX"
        );

        assertEq(
            IERC20(MC.FXBASE).balanceOf(address(withdrawer)),
            fxBaseObtained,
            "fxBASE balance should be equal to fxBASE obtained"
        );

        uint256 withdrawerTotalBaseAssetsBefore = withdrawer.totalBaseAssets();

        requestRedeemForFxBase(fxBaseObtained);

        vm.assertApproxEqAbs(
            withdrawer.totalBaseAssets(),
            withdrawerTotalBaseAssetsBefore,
            3,
            "withdrawer totalBaseAssets should remain approx constant after requestRedeemForFxBase"
        );

        // Assert after requestRedeemForFxBase (allowing approx abs diff of 1 wei)
        vm.assertApproxEqAbs(
            vault.totalBaseAssets(),
            totalBaseAssetsAfterFxBaseAllocation,
            3,
            "totalBaseAssets should remain approx constant after requestRedeemForFxBase"
        );

        {
            IFxUSDBasePool fxBase = IFxUSDBasePool(MC.FXBASE);
            IFxUSDBasePool.RedeemRequest memory redeemRequest = fxBase.redeemRequests(address(withdrawer));
            // skip time to unlockAt
            vm.warp(redeemRequest.unlockAt + 1);
        }

        withdrawer.processAccounting();
        vault.processAccounting();

        uint256 totalBaseAssetsBeforeRedeem = vault.totalBaseAssets();

        // yield kicks in after time passes
        assertGt(
            totalBaseAssetsBeforeRedeem,
            totalBaseAssetsAfterFxBaseAllocation,
            "totalBaseAssetsBeforeRedeem should be greater than totalBaseAssetsAfterFxBaseAllocation"
        );

        // Calculate how much was redeemed
        uint256 usdcRedeemed = 0;
        uint256 fxusdRedeemed = 0;

        {
            // Get USDC and FXUSD balances in withdrawer before redeem
            uint256 usdcBefore = IERC20(MC.USDC).balanceOf(address(withdrawer));
            uint256 fxusdBefore = IERC20(MC.FXUSD).balanceOf(address(withdrawer));

            redeemFromFxBase(fxBaseObtained);

            // Assert after redeemFromFxBase (allowing approx abs diff of 1 wei)
            vm.assertApproxEqRel(
                vault.totalBaseAssets(),
                totalBaseAssetsBeforeRedeem,
                1e12,
                "totalBaseAssets should remain approx constant after redeemFromFxBase"
            );

            // Get USDC and FXUSD balances in withdrawer after redeem
            uint256 usdcAfter = IERC20(MC.USDC).balanceOf(address(withdrawer));
            uint256 fxusdAfter = IERC20(MC.FXUSD).balanceOf(address(withdrawer));

            // Calculate how much was redeemed
            usdcRedeemed = usdcAfter > usdcBefore ? usdcAfter - usdcBefore : 0;
            fxusdRedeemed = fxusdAfter > fxusdBefore ? fxusdAfter - fxusdBefore : 0;
        }

        {
            // Record vault's FXUSD balance before withdrawal
            uint256 fxusdVaultBefore = IERC20(MC.FXUSD).balanceOf(address(vault));

            {
                uint256 usdcWithdrawn = usdcRedeemed > 1e6 ? usdcRedeemed - 1e6 : 0;
                if (usdcWithdrawn > 0) {
                    ProcessorUtils.withdrawFromERC4626(address(vault), address(withdrawer), usdcWithdrawn, PROCESSOR);
                }
            }

            ProcessorUtils.withdrawAssetFromERC4626MAX(
                address(vault), address(withdrawer), MC.FXUSD, fxusdRedeemed, PROCESSOR
            );

            // Assert that vault's FXUSD balance increased by the redeemed amount (allowing for 1 wei tolerance)
            uint256 fxusdVaultAfter = IERC20(MC.FXUSD).balanceOf(address(vault));
            assertEq(
                fxusdVaultAfter,
                fxusdVaultBefore + fxusdRedeemed,
                "Vault FXUSD balance should increase by redeemed amount"
            );

            withdrawer.processAccounting();
            vault.processAccounting();
        }

        vm.assertApproxEqRel(
            vault.totalBaseAssets(),
            totalBaseAssetsBeforeRedeem,
            1e12,
            "totalBaseAssets should remain approx constant after all redemptions"
        );
    }

    function test_deposit_fxsave_external_sample() public {
        uint256 depositAmount = 1_000_000e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        IFxUSDBasePool fxBase = IFxUSDBasePool(MC.FXBASE);

        // Use the following to previewRedeem
        // (uint256 presumedFxBaseYield, uint256 presumedFxBaseStable) = fxBase.previewRedeem(presumedSharesAmount);
        // Step 1: Deposit USDC into fxBASE using the interface
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(fxBase), depositAmount);

        // .nav() records chainlink oracle based pricing. Do NOT use for fundamental value oracles.
        //uint256 navBefore = fxBase.nav();

        // Use the IFxUSDBasePool interface to deposit USDC into fxBASE using the correct signature
        fxBase.deposit(
            alice, // receiver
            MC.USDC, // tokenIn
            depositAmount, // amountTokenToDeposit
            0 // minSharesOut
        );

        // Step 2: Deposit fxBASE shares into fxSAVE (as ERC4626)
        uint256 fxBaseBalance = IERC20(address(fxBase)).balanceOf(alice);
        IERC20(address(fxBase)).approve(MC.FXSAVE, fxBaseBalance);
        IERC4626(MC.FXSAVE).deposit(fxBaseBalance, alice);

        vm.stopPrank();

        // Measure alice's balance in fxSAVE (shares)
        uint256 fxSaveShares = IERC20(MC.FXSAVE).balanceOf(alice);

        {
            vm.startPrank(alice);

            IERC4626(MC.FXSAVE).redeem(fxSaveShares, alice, alice);

            uint256 sharesToRedeem = fxBase.balanceOf(alice);

            fxBase.requestRedeem(sharesToRedeem);

            IFxUSDBasePool.RedeemRequest memory redeemRequest = fxBase.redeemRequests(alice);

            // skip time to unlockAt
            vm.warp(redeemRequest.unlockAt + 1);

            fxBase.redeem(alice, sharesToRedeem);

            vm.stopPrank();
        }
    }
}

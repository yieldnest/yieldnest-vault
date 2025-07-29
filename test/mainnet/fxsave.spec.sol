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
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";

contract SuperUSDCTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        vm.stopPrank();
        bufferStrategy = MC.MORPHO_GAUNTLET_USDC_VAULT;
    }

    function test_deposit_fxsave() public {
        uint256 depositAmount = 10_000_000e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        uint256 presumedSharesAmount = depositAmount * 1e12;
        uint256 presumedFxBaseAssets = IERC4626(MC.FXBASE).previewRedeem(presumedSharesAmount);
        console.log("presumedSharesAmount", presumedSharesAmount);
        console.log("presumedFxBaseAssets", presumedFxBaseAssets);

        // Step 1: Deposit USDC into fxBASE using the interface
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(MC.FXBASE, depositAmount);

        // Use the IFxUSDBasePool interface to deposit USDC into fxBASE using the correct signature
        IFxUSDBasePool(MC.FXBASE).deposit(
            alice, // receiver
            MC.USDC, // tokenIn
            depositAmount, // amountTokenToDeposit
            0 // minSharesOut
        );

        console.log("presumedFxAssets in between ", IERC4626(MC.FXBASE).previewRedeem(presumedSharesAmount));

        // Step 2: Deposit fxBASE shares into fxSAVE (as ERC4626)
        uint256 fxBaseBalance = IERC20(MC.FXBASE).balanceOf(alice);
        IERC20(MC.FXBASE).approve(MC.FXSAVE, fxBaseBalance);
        IERC4626(MC.FXSAVE).deposit(fxBaseBalance, alice);

        vm.stopPrank();

        {
            // Measure alice's balance in fxSAVE (shares)
            uint256 fxSaveShares = IERC20(MC.FXSAVE).balanceOf(alice);

            console.log("fxSaveShares", fxSaveShares);

            // Convert shares to USDC value using convertToAssets
            uint256 fxBaseAssets = IERC4626(MC.FXSAVE).convertToAssets(fxSaveShares);
            console.log("fxBaseAssets", fxBaseAssets);

            uint256 fxBaseAssetsInUSDC = fxBaseAssets * IFxUSDBasePool(MC.FXBASE).nav() / 1e18;

            console.log("fxBaseAssetsInUSDC", fxBaseAssetsInUSDC);

            uint256 previewRedeem = IERC4626(MC.FXBASE).previewRedeem(fxBaseAssets);
            console.log("previewRedeem", previewRedeem);

            console.log("presumedFxAssets After ", IERC4626(MC.FXBASE).previewRedeem(presumedSharesAmount));
        }
    }
}

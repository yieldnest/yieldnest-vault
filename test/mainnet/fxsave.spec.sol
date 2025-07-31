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

    function convertToUSDC(uint256 shares) public view returns (uint256) {
        IFxUSDBasePool fxBase = IFxUSDBasePool(MC.FXBASE);

        (uint256 yieldTokenAmount, uint256 fxStableAmount) = fxBase.previewRedeem(shares);
        return yieldTokenAmount + fxStableAmount * 1e12;
    }

    // function test_allocate_to_fxsave() public {
    //     uint256 allocationAmount = 1_000_000e6;
    //     allocateToBuffer(allocationAmount);
    // }

    function test_deposit_fxsave() public {
        uint256 depositAmount = 1_000_000e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        IFxUSDBasePool fxBase = IFxUSDBasePool(MC.FXBASE);

        uint256 presumedSharesAmount = depositAmount * 1e12;
        (uint256 presumedFxBaseYield, uint256 presumedFxBaseStable) = fxBase.previewRedeem(presumedSharesAmount);
        console.log("presumedSharesAmount", presumedSharesAmount);
        console.log("presumedFxBaseYield", presumedFxBaseYield);
        console.log("presumedFxBaseStable", presumedFxBaseStable);

        // Step 1: Deposit USDC into fxBASE using the interface
        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(fxBase), depositAmount);

        // Log USDC balance in fxBASE before deposit
        console.log("USDC in fxBASE before deposit:", IERC20(MC.USDC).balanceOf(address(fxBase)));
        console.log("totalStableToken before deposit:", fxBase.totalStableToken());
        console.log("totalYieldToken before deposit:", fxBase.totalYieldToken());

        console.log("convertToUSDC before deposit", convertToUSDC(1e18));

        // Record nav before deposit
        uint256 navBefore = fxBase.nav();

        // Use the IFxUSDBasePool interface to deposit USDC into fxBASE using the correct signature
        fxBase.deposit(
            alice, // receiver
            MC.USDC, // tokenIn
            depositAmount, // amountTokenToDeposit
            0 // minSharesOut
        );

        // Record nav after deposit
        uint256 navAfter = fxBase.nav();

        // Log USDC balance in fxBASE after deposit
        console.log("USDC in fxBASE after deposit:", IERC20(MC.USDC).balanceOf(address(fxBase)));
        console.log("totalStableToken after deposit:", fxBase.totalStableToken());
        console.log("totalYieldToken after deposit:", fxBase.totalYieldToken());

        console.log("convertToUSDC after deposit", convertToUSDC(1e18));

        // Print difference in nav before and after
        console.log("nav difference after deposit:", int256(navAfter) - int256(navBefore));

        (uint256 presumedFxBaseYieldMid, uint256 presumedFxBaseStableMid) = fxBase.previewRedeem(presumedSharesAmount);
        console.log("presumedFxAssets in between (yield)", presumedFxBaseYieldMid);
        console.log("presumedFxAssets in between (stable)", presumedFxBaseStableMid);

        // Step 2: Deposit fxBASE shares into fxSAVE (as ERC4626)
        uint256 fxBaseBalance = IERC20(address(fxBase)).balanceOf(alice);
        IERC20(address(fxBase)).approve(MC.FXSAVE, fxBaseBalance);
        IERC4626(MC.FXSAVE).deposit(fxBaseBalance, alice);

        vm.stopPrank();

        // Measure alice's balance in fxSAVE (shares)
        uint256 fxSaveShares = IERC20(MC.FXSAVE).balanceOf(alice);
        {
            console.log("fxSaveShares", fxSaveShares);

            // Convert shares to USDC value using convertToAssets
            uint256 fxBaseAssets = IERC4626(MC.FXSAVE).convertToAssets(fxSaveShares);
            console.log("fxBaseAssets", fxBaseAssets);

            uint256 fxBaseAssetsInUSDC = fxBaseAssets * fxBase.nav() / 1e18;

            console.log("fxBaseAssetsInUSDC", fxBaseAssetsInUSDC);

            console.log("convertToUSDC", convertToUSDC(fxBaseAssets));

            (uint256 presumedFxBaseYieldAfter, uint256 presumedFxBaseStableAfter) =
                fxBase.previewRedeem(presumedSharesAmount);
            console.log("presumedFxAssets After (yield)", presumedFxBaseYieldAfter);
            console.log("presumedFxAssets After (stable)", presumedFxBaseStableAfter);
        }

        {
            vm.startPrank(alice);

            IERC4626(MC.FXSAVE).redeem(fxSaveShares, alice, alice);

            console.log("fxBase.balanceOf(alice)", fxBase.balanceOf(alice));

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

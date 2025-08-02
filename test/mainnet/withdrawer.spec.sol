// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "src/interface/IVault.sol";
import {ProcessorUtils} from "test/utils/ProcessorUtils.sol";

contract WithdrawerTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;

    function setUp() public {
        (vault,) = BaseTest.deploy();
    }

    function test_Withdrawer_deposit_and_withdraw_usdc(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1e6, 10_000_000e6);
        withdrawAmount = bound(withdrawAmount, 1e6, depositAmount);

        uint256 totalAssetsBefore = vault.totalAssets();

        {
            // Give USDC to alice and have her deposit into the vault
            address alice = makeAddr("alice");
            deal(MC.USDC, alice, depositAmount);

            vm.startPrank(alice);
            IERC20(MC.USDC).approve(address(vault), depositAmount);
            vault.deposit(depositAmount, alice);
            vm.stopPrank();
        }

        ProcessorUtils.allocateToERC4626(address(vault), MC.USDC, address(withdrawer), depositAmount, PROCESSOR);

        uint256 totalAssetsAfter = vault.totalAssets();
        // Assert that totalAssetsAfter is approximately equal to totalAssetsBefore + depositAmount
        // Allow a small absolute difference due to rounding, e.g., 1 wei
        vm.assertApproxEqAbs(
            totalAssetsAfter,
            totalAssetsBefore + depositAmount,
            1,
            "totalAssetsAfter should be approx totalAssetsBefore + depositAmount"
        );

        // Withdraw USDC from the withdrawer using ProcessorUtils
        ProcessorUtils.withdrawFromERC4626(address(vault), address(withdrawer), withdrawAmount, PROCESSOR);

        vm.assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore + depositAmount,
            1,
            "totalAssetsAfter should be approx totalAssetsAfter - withdrawAmount"
        );
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, Math, TimelockController} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Provider} from "src/module/Provider.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseVault} from "src/BaseVault.sol";
import {IVault} from "src/interface/IVault.sol";
import {console} from "forge-std/console.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract VaultBufferInvariantsTest is BaseTest {
    using SafeERC20 for IERC20;

    Vault public vault;
    address public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        // Process accounting to ensure vault is in sync
        vault.processAccounting();
        bufferStrategy = vault.buffer();
    }

    function allocateToBuffer(uint256 depositAmount) public returns (uint256 bufferStrategySharesMinted) {
        // Allocate to buffer (MorphoGauntletUSDC core vault)
        {
            address[] memory targets = new address[](2);
            uint256[] memory values = new uint256[](2);
            bytes[] memory data = new bytes[](2);

            targets[0] = MC.USDC;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (address(vault.buffer()), depositAmount));

            targets[1] = vault.buffer();
            values[1] = 0;
            data[1] = abi.encodeCall(IERC4626.deposit, (depositAmount, address(vault)));

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();

            bufferStrategySharesMinted = abi.decode(returnData[1], (uint256));
        }
        vault.processAccounting();
    }

    function test_allocate_to_buffer_strategy(uint256 userDepositAmount, uint256 bufferDepositAmount) public {
        address alice = makeAddr("alice");
        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);
        bufferDepositAmount = bound(bufferDepositAmount, 1000, userDepositAmount);

        uint256 expectedSharesToReceive = vault.previewDeposit(userDepositAmount);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 baseAssetsOfVaultBefore = vault.totalBaseAssets();
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        vault.processAccounting();

        assertEq(expectedSharesToReceive, vault.balanceOf(alice), "Shares should be equal to previewDeposit");

        totalSupplyInvariant(totalSupplyBefore + expectedSharesToReceive);
        totalAssetsInvariant(totalAssetsBefore + userDepositAmount);
        assertEq(
            vault.totalBaseAssets(),
            userDepositAmount * 1e12 + baseAssetsOfVaultBefore,
            "Vault should have the same total base assets as the user deposit amount scaled by 1e12"
        );

        totalAssetsBefore = vault.totalAssets();
        totalSupplyBefore = vault.totalSupply();

        uint256 bufferStrategySharesMinted;
        uint256 expectedShareBalanceOfMorphoGauntletUsdcVault;
        uint256 bufferStrategyBalanceOfVaultBefore = IERC20(bufferStrategy).balanceOf(address(vault));
        uint256 initialSharesOfMorphoGauntletUsdcVault;
        {
            // allocate to buffer
            uint256 usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
            initialSharesOfMorphoGauntletUsdcVault = IERC20(MC.MORPHO_GAUNTLET_USDC_VAULT).balanceOf(address(vault));
            expectedShareBalanceOfMorphoGauntletUsdcVault =
                IERC4626(MC.MORPHO_GAUNTLET_USDC_VAULT).previewDeposit(bufferDepositAmount);

            bufferStrategySharesMinted = allocateToBuffer(bufferDepositAmount);

            uint256 usdcBalanceOfVaultAfter = IERC20(MC.USDC).balanceOf(address(vault));
            uint256 usdcBalanceOfBufferAfter = IERC20(MC.USDC).balanceOf(vault.buffer());
            assertEq(
                usdcBalanceOfVaultBefore - usdcBalanceOfVaultAfter,
                bufferDepositAmount,
                "USDC balance should decrease by amount deposited in buffer"
            );
        }

        assertGt(bufferStrategySharesMinted, 0, "Buffer shares should be greater than 0");
        assertEq(
            IERC20(MC.MORPHO_GAUNTLET_USDC_VAULT).balanceOf(address(vault)),
            expectedShareBalanceOfMorphoGauntletUsdcVault + initialSharesOfMorphoGauntletUsdcVault,
            "Incorrect gauntlet usdc vault balance in buffer strategy"
        );
        assertEq(
            IERC20(bufferStrategy).balanceOf(address(vault)),
            bufferStrategySharesMinted + bufferStrategyBalanceOfVaultBefore,
            "Incorrect share amount of bufferStrategyShares in vault"
        );
        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore,
            1e7,
            "Vault total assets should be similar to before ignorning rounding errors"
        );
        totalSupplyInvariant(totalSupplyBefore);
    }

    function test_withdraw_Buffer_6Decimals() public {
        if (vault.buffer() != MC.EVK_VAULT_EUSDC_95) {
            // Give admin the BUFFER_MANAGER_ROLE and set the buffer to EVK_VAULT_EUSDC_95

            // Grant BUFFER_MANAGER_ROLE to ADMIN (calling as TIMELOCK or whoever is the role admin)
            vm.startPrank(ADMIN);
            vault.grantRole(vault.BUFFER_MANAGER_ROLE(), ADMIN);
            vm.stopPrank();

            // Set buffer to EVK Vault (with the admin now able to set the buffer)
            vm.startPrank(ADMIN);
            vault.setBuffer(MC.EVK_VAULT_EUSDC_95);
            vm.stopPrank();
        }
        // Assume MC.EULER exists. If not, replace this check with actual "euler thing" logic.
        // Ensure user has enough USDC to deposit
        address user = makeAddr("alice");
        uint256 depositAmount = 100_000 * 1e6; // 100,000 USDC (6 decimals)
        deal(MC.USDC, user, depositAmount);

        // Deposit USDC into the vault
        _depositAssetToVault(MC.USDC, depositAmount, user);

        // Allocate to buffer
        allocateToBuffer(depositAmount);

        // Record state before withdraw
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        uint256 rateBefore = IERC4626(vault.buffer()).convertToAssets(1e18);

        // Withdraw from buffer
        uint256 withdrawAmount = depositAmount / 2; // withdraw half

        uint256 userBalanceBefore = IERC20(MC.USDC).balanceOf(user);

        // Record buffer total assets before withdraw
        uint256 bufferTotalAssetsBefore = IERC4626(vault.buffer()).totalAssets();

        vm.startPrank(user);
        uint256 burnedShares = vault.withdraw(withdrawAmount, user, user);
        vm.stopPrank();

        vault.processAccounting();

        uint256 userBalanceAfter = IERC20(MC.USDC).balanceOf(user);

        // Assert Alice actually gets withdrawAmount (allowing for minor dust from rounding)
        assertApproxEqAbs(
            userBalanceAfter,
            userBalanceBefore + withdrawAmount,
            1, // small tolerance for rounding dust (may adjust depending on vault logic)
            "User should receive the expected withdrawAmount in USDC"
        );

        // State after withdraw
        uint256 totalAssetsAfter = vault.totalAssets();
        uint256 totalSupplyAfter = vault.totalSupply();
        uint256 rateAfter = IERC4626(vault.buffer()).convertToAssets(1e18);

        // Assets should have gone down ~withdrawAmount
        assertApproxEqAbs(
            vault.totalAssets(),
            totalAssetsBefore - withdrawAmount,
            1,
            "totalAssets should decrease by withdrawn amount"
        );
        // Buffer assets should have gone down ~withdrawAmount as well
        assertApproxEqAbs(
            IERC4626(vault.buffer()).totalAssets(),
            bufferTotalAssetsBefore - withdrawAmount,
            1,
            "Buffer total assets should decrease by withdrawn amount"
        );
        // Supply should decrease (user shares burned)
        assertEq(totalSupplyAfter, totalSupplyBefore - burnedShares, "Total supply should decrease after withdrawal");

        // Rate should increase after withdrawal due to fees accrued during withdrawal
        assertGt(rateAfter, rateBefore, "Rate should increase because of withdrawal fees");
    }

    function _depositAssetToVault(address asset, uint256 amount, address user) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(vault), amount);
        vault.depositAsset(asset, amount, user);
        vm.stopPrank();
    }
}

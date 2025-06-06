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
        bufferStrategy = MC.MORPHO_GAUNTLET_USDC_VAULT;
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

    function test_allocate_to_buffer_strategy(uint256 userDepositAmount, uint256 bufferDepositAmount) public {
        address alice = makeAddr("alice");
        userDepositAmount = bound(userDepositAmount, 1000, 1_000_000 * 1e6);
        bufferDepositAmount = bound(bufferDepositAmount, 1000, userDepositAmount);

        uint256 expectedSharesToReceive = vault.previewDeposit(userDepositAmount);
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        deal(MC.USDC, alice, userDepositAmount);
        _depositAssetToVault(MC.USDC, userDepositAmount, alice);

        vault.processAccounting();

        console.log("totalAssets", vault.totalAssets());
        console.log("totalSupply", vault.totalSupply());

        assertEq(
            expectedSharesToReceive,
            userDepositAmount * 1e12,
            "Shares should be equal to amount deposited scaled by 1e12"
        );

        totalSupplyInvariant(totalSupplyBefore + expectedSharesToReceive);
        totalAssetsInvariant(totalAssetsBefore + userDepositAmount);
        assertEq(
            vault.totalBaseAssets(),
            userDepositAmount * 1e12,
            "Vault should have the same total base assets as the user deposit amount scaled by 1e12"
        );

        totalAssetsBefore = vault.totalAssets();
        totalSupplyBefore = vault.totalSupply();

        uint256 bufferStrategySharesMinted;
        uint256 expectedShareBalanceOfMorphoGauntletUsdcVault;
        {
            // allocate to buffer
            uint256 usdcBalanceOfVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
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
            assertEq(
                usdcBalanceOfBufferAfter,
                0,
                "Buffer balance should be allocated to usdc core vault due to sync deposit on"
            );
        }

        assertGt(bufferStrategySharesMinted, 0, "Buffer shares should be greater than 0");
        assertEq(
            IERC20(MC.MORPHO_GAUNTLET_USDC_VAULT).balanceOf(address(vault)),
            expectedShareBalanceOfMorphoGauntletUsdcVault,
            "Incorrect gauntlet usdc vault balance in buffer strategy"
        );
        assertEq(
            IERC20(bufferStrategy).balanceOf(address(vault)),
            bufferStrategySharesMinted,
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

    function _depositAssetToVault(address asset, uint256 amount, address user) internal {
        vm.startPrank(user);
        IERC20(asset).approve(address(vault), amount);
        vault.depositAsset(asset, amount, user);
        vm.stopPrank();
    }
}

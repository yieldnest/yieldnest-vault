// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC, MainnetStrategyContracts as MSC } from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20, IERC4626} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ICurveRegistry} from "test/interface/external/curve/ICurveRegistry.sol";
import {ICurvePool} from "test/interface/external/curve/ICurvePool.sol";
import {IStETH} from "test/interface/external/lido/IStETH.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {console} from "lib/forge-std/src/console.sol";


interface IynETH {
    function depositETH(address receiver) external payable returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);
}

contract VaultStrategiesTest is Test, AssertUtils, MainnetActors {

    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade();
        vault = Vault(payable(MC.YNETHX));

        // Grant DEFAULT_ADMIN_ROLE to setup contract
        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(setup));
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(setup));
        vm.stopPrank();

        configureLendingStrategiesActions(setup, vault);

        // Remove DEFAULT_ADMIN_ROLE from setup contract
        vm.startPrank(ADMIN);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), address(setup));
        vault.revokeRole(vault.PROCESSOR_MANAGER_ROLE(), address(setup));
        vm.stopPrank();
    }
    function configureLendingStrategiesActions(SetupVault setup, Vault _vault) internal {

        // vm.startPrank(ADMIN);

        // // Get ethSteth pool from registry
        // ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        // address ethStethPool = registry.find_pool_for_coins(MC.ETH, MC.STETH);

        // // Get ynETHWstETH pool from two crypto factory
        // address ynETHWstETHPool = ICurveRegistry(MC.CURVE_TWOCRYPTO_FACTORY).find_pool_for_coins(MC.YNETH, MC.WSTETH);

        // // Add curve pools to array
        // address[] memory curvePools = new address[](2);
        // curvePools[0] = ethStethPool;
        // curvePools[1] = ynETHWstETHPool;

        // // Add curve pool actions
        // for (uint256 i = 0; i < curvePools.length; i++) {

        //     // Exchange function
        //     bytes4 exchange = bytes4(keccak256("exchange(int128,int128,uint256,uint256)"));
        //     IVault.ParamRule[] memory exchangeRules = new IVault.ParamRule[](4);
        //     exchangeRules[0] = IVault.ParamRule({
        //         paramType: IVault.ParamType.UINT256,
        //         isArray: false,
        //         allowList: new address[](0)
        //     });
        //     exchangeRules[1] = IVault.ParamRule({
        //         paramType: IVault.ParamType.UINT256,
        //         isArray: false,
        //         allowList: new address[](0)
        //     });
        //     exchangeRules[2] = IVault.ParamRule({
        //         paramType: IVault.ParamType.UINT256,
        //         isArray: false,
        //         allowList: new address[](0)
        //     });
        //     exchangeRules[3] = IVault.ParamRule({
        //         paramType: IVault.ParamType.UINT256,
        //         isArray: false,
        //         allowList: new address[](0)
        //     });

        //     _vault.setProcessorRule(curvePools[i], exchange, IVault.FunctionRule({
        //         isActive: true,
        //         paramRules: exchangeRules,
        //         validator: IValidator(address(0))
        //     }));
        // }
        // // Set approval rule to allow ethStethPool to spend stETH tokens from the vault
        // setup.setApprovalRule(_vault, MC.STETH, ethStethPool);

        // // Set approval rules for ynETH and wstETH to be spent by ynETHWstETH pool
        // setup.setApprovalRule(_vault, MC.YNETH, ynETHWstETHPool);
        // setup.setApprovalRule(_vault, MC.WSTETH, ynETHWstETHPool);

        // vm.stopPrank();
    }

    function test_MorphoVaultDepositWithdraw() public {
        
        // Get initial WETH balance
        uint256 initialBalance = IERC20(MC.WETH).balanceOf(address(this));

        // Deposit amount
        uint256 depositAmount = 1e18; // 1 WETH

        address BOB = address(0x5678);

        // Give Bob 10000 WETH
        uint256 bobInitialBalance = 10000e18;

        {
            deal(BOB, bobInitialBalance);
            vm.startPrank(BOB);
            (bool success,) = MC.WETH.call{value: bobInitialBalance}("");
            require(success, "ETH to WETH failed");
            vm.stopPrank();
        }

        vm.startPrank(BOB);

        // Set targetVault to the appropriate vault address
        address targetVault = MSC.GAUNTLET_WETH_PRIME;

        // Approve WETH to the target vault
        IERC20(MC.WETH).approve(targetVault, depositAmount);

        // Deposit WETH to the target vault
        uint256 shares = IERC4626(targetVault).deposit(depositAmount, BOB);
        assertGt(shares, 0, "Should receive shares for deposit");

        // Check WETH was transferred
        uint256 bobBalanceAfterDeposit = IERC20(MC.WETH).balanceOf(BOB);
        assertEq(
            bobBalanceAfterDeposit,
            bobInitialBalance - depositAmount,
            "WETH should be transferred from Bob"
        );

        // Log deposit details
        console.log("Deposit amount: %d WETH", depositAmount / 1e18);
        console.log("Shares received: %d", shares);
        console.log("WETH balance after deposit: %d", bobBalanceAfterDeposit / 1e18);

        // Assert the value of redeeming the shares using convertToAssets is roughly equal to deposit amount
        uint256 redeemableAssets = IERC4626(targetVault).convertToAssets(shares);
        assertApproxEqAbs(
            redeemableAssets,
            depositAmount,
            1,
            "Redeemable assets should be approximately equal to the deposit amount"
        );

        // Redeem full shares amount
        IERC4626(targetVault).redeem(shares, BOB, BOB);

        // Verify WETH balance is restored
        uint256 bobBalanceAfterWithdraw = IERC20(MC.WETH).balanceOf(BOB);
        assertApproxEqAbs(
            bobBalanceAfterWithdraw,
            bobInitialBalance,
            1,
            "Should receive original WETH amount back"
        );
        vm.stopPrank();
    }
}
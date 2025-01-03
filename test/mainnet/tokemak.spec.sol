// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
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

contract VaultMainnetTokemakTest is Test, AssertUtils, MainnetActors {

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

        configureTokemakActions(setup, vault);

        // Remove DEFAULT_ADMIN_ROLE from setup contract
        vm.startPrank(ADMIN);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), address(setup));
        vault.revokeRole(vault.PROCESSOR_MANAGER_ROLE(), address(setup));
        vm.stopPrank();
    }
    function configureTokemakActions(SetupVault setup, Vault _vault) internal {

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

    function test_TokemakAutoEthDepositWithdraw() public {
        // Get initial WETH balance
        uint256 initialBalance = IERC20(MC.WETH).balanceOf(address(this));

        // Deposit amount
        uint256 depositAmount = 1e18; // 1 WETH

        address ALICE = address(0x1234);


        // Give Alice 10000 WETH
        uint256 aliceInitialBalance = 10000e18;

        {
            deal(ALICE, aliceInitialBalance);
            vm.startPrank(ALICE);
            (bool success,) = MC.WETH.call{value: aliceInitialBalance}("");
            require(success, "ETH to WETH failed");
            vm.stopPrank();
        }


        vm.startPrank(ALICE);
  

        // Approve WETH to tokemak autoETH
        IERC20(MC.WETH).approve(MC.TOKEMAK_AUTOETH, depositAmount);

        // Deposit WETH to tokemak autoETH
        uint256 shares = IERC4626(MC.TOKEMAK_AUTOETH).deposit(depositAmount, ALICE);
        assertGt(shares, 0, "Should receive shares for deposit");

        // Check WETH was transferred
        uint256 aliceBalanceAfterDeposit = IERC20(MC.WETH).balanceOf(ALICE);
        assertEq(
            aliceBalanceAfterDeposit,
            aliceInitialBalance - depositAmount,
            "WETH should be transferred from Alice"
        );

        // Log deposit details
        console.log("Deposit amount: %d WETH", depositAmount / 1e18);
        console.log("Shares received: %d", shares);
        console.log("WETH balance after deposit: %d", aliceBalanceAfterDeposit / 1e18);

        // // Withdraw full amount
        // IERC4626(MC.TOKEMAK_AUTOETH).withdraw(depositAmount, ALICE, ALICE);

        // // Verify WETH balance is restored
        // uint256 aliceBalanceAfterWithdraw = IERC20(MC.WETH).balanceOf(ALICE);
        // assertEq(
        //     aliceBalanceAfterWithdraw,
        //     aliceInitialBalance,
        //     "Should receive original WETH amount back"
        // );

        vm.stopPrank();
    }
}
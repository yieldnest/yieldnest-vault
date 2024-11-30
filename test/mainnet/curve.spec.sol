// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ICurveRegistry} from "test/interface/external/curve/ICurveRegistry.sol";
import {ICurvePool} from "test/interface/external/curve/ICurvePool.sol";
import {IStETH} from "test/interface/external/lido/IStETH.sol";
import {IValidator} from "src/interface/IValidator.sol";



interface IynETH {
    function depositETH(address receiver) external payable returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);
}

contract VaultMainnetCurveTest is Test, AssertUtils, MainnetActors {

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

        configureCurveActions(setup, vault);

        // Remove DEFAULT_ADMIN_ROLE from setup contract
        vm.startPrank(ADMIN);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), address(setup));
        vault.revokeRole(vault.PROCESSOR_MANAGER_ROLE(), address(setup));
        vm.stopPrank();
    }
    function configureCurveActions(SetupVault setup, Vault _vault) internal {

        vm.startPrank(ADMIN);

        // Get ethSteth pool from registry
        ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        address ethStethPool = registry.find_pool_for_coins(MC.ETH, MC.STETH);

        // Get ynETHWstETH pool from two crypto factory
        address ynETHWstETHPool = ICurveRegistry(MC.CURVE_TWOCRYPTO_FACTORY).find_pool_for_coins(MC.YNETH, MC.WSTETH);

        // Add curve pools to array
        address[] memory curvePools = new address[](2);
        curvePools[0] = ethStethPool;
        curvePools[1] = ynETHWstETHPool;

        // Add curve pool actions
        for (uint256 i = 0; i < curvePools.length; i++) {

            // Exchange function
            bytes4 exchange = bytes4(keccak256("exchange(int128,int128,uint256,uint256)"));
            IVault.ParamRule[] memory exchangeRules = new IVault.ParamRule[](4);
            exchangeRules[0] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });
            exchangeRules[1] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });
            exchangeRules[2] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });
            exchangeRules[3] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });

            _vault.setProcessorRule(curvePools[i], exchange, IVault.FunctionRule({
                isActive: true,
                paramRules: exchangeRules,
                validator: IValidator(address(0))
            }));
        }
        // Set approval rule to allow ethStethPool to spend stETH tokens from the vault
        setup.setApprovalRule(_vault, MC.STETH, ethStethPool);

        // Set approval rules for ynETH and wstETH to be spent by ynETHWstETH pool
        setup.setApprovalRule(_vault, MC.YNETH, ynETHWstETHPool);
        setup.setApprovalRule(_vault, MC.WSTETH, ynETHWstETHPool);

        vm.stopPrank();
    }

    function test_Vault_Curve_swapStETHtoETH() public {
        uint256 amount = 100 ether;

        // Create user and give them ETH
        address user = makeAddr("user");
        deal(user, 100000 ether);

        // Convert ETH to stETH via Lido
        vm.startPrank(user);
        IStETH(MC.STETH).submit{value: amount + 100 wei }(address(0));
        vm.stopPrank();

        // Approve and deposit stETH to vault
        vm.startPrank(user);
        IERC20(MC.STETH).approve(address(vault), amount);
        vault.depositAsset(MC.STETH, amount, user);
        vm.stopPrank();

        // Read total assets before swap
        uint256 totalAssetsBefore = vault.totalAssets();


        // Exchange stETH for ETH via Curve pool
        ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        ICurvePool pool = ICurvePool(registry.find_pool_for_coins(MC.ETH, MC.STETH));

        uint256 swapAmount = amount / 2;

        uint256 minOut = pool.get_dy(1, 0, swapAmount); // Swap from stETH (1) to ETH (0)

        uint256 delta = swapAmount - minOut + 2 wei; // wei difference from stETH balance error

        // Prepare approve data
        bytes memory approveData = abi.encodeWithSelector(
            IERC20.approve.selector,
            address(pool),
            swapAmount
        );

        // Prepare exchange data
        bytes memory exchangeData = abi.encodeWithSelector(
            bytes4(keccak256("exchange(int128,int128,uint256,uint256)")),
            1, // stETH index
            0, // ETH index
            swapAmount,
            minOut
        );

        {
            address[] memory targets = new address[](2);
            targets[0] = MC.STETH;
            targets[1] = address(pool);

            uint256[] memory values = new uint256[](2);
            values[0] = 0;
            values[1] = 0;

            bytes[] memory callData = new bytes[](2);
            callData[0] = approveData;
            callData[1] = exchangeData;

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, callData);
            vm.stopPrank();
        }

        // Assert stETH balance is 0 and ETH balance matches expected amount
        assertApproxEqAbs(IERC20(MC.STETH).balanceOf(address(vault)), amount - swapAmount, 2);
        assertApproxEqAbs(address(vault).balance, minOut, 2);

        vault.processAccounting();

        // Assert total assets remains unchanged after swap
        assertApproxEqAbs(vault.totalAssets(), totalAssetsBefore, delta);
    }

    function test_Vault_Curve_swapETHToStETH() public {
        uint256 amount = 100 ether;

        // User deposits ETH
        address user = makeAddr("user");
        vm.deal(user, amount);
        vm.startPrank(user);
        (bool success,) = address(vault).call{value: amount}("");
        require(success, "ETH transfer failed");
        vm.stopPrank();

        // Get curve pool for ETH/stETH
        ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        ICurvePool pool = ICurvePool(registry.find_pool_for_coins(MC.ETH, MC.STETH));

        uint256 swapAmount = amount / 2;
        uint256 minOut = pool.get_dy(0, 1, swapAmount); // Swap from ETH (0) to stETH (1)

        // Prepare exchange data
        bytes memory exchangeData = abi.encodeWithSelector(
            bytes4(keccak256("exchange(int128,int128,uint256,uint256)")),
            0, // ETH index
            1, // stETH index
            swapAmount,
            minOut
        );

        {
            address[] memory targets = new address[](1);
            targets[0] = address(pool);

            uint256[] memory values = new uint256[](1);
            values[0] = swapAmount; // Send ETH with the call

            bytes[] memory callData = new bytes[](1);
            callData[0] = exchangeData;

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, callData);
            vm.stopPrank();
        }

        // Assert ETH balance is reduced and stETH balance matches expected amount
        assertApproxEqAbs(address(vault).balance, amount - swapAmount, 2);
        assertApproxEqAbs(IERC20(MC.STETH).balanceOf(address(vault)), minOut, 2);
    }
}
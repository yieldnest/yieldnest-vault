// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault,IVault} from "src/Vault.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {ICurveRegistry} from "src/interface/external/curve/ICurveRegistry.sol";
import {ICurvePool} from "src/interface/external/curve/ICurvePool.sol";
import {IStETH} from "src/interface/external/lido/IStETH.sol";
import {console} from "lib/forge-std/src/console.sol";


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

    function test_Vault_Curve_addLiquidity() public {
        uint256 ethAmount = 100 ether;
        uint256 stethAmount = 100 ether;

        // User deposits ETH
        address user = makeAddr("user");
        vm.deal(user, ethAmount + stethAmount);
        vm.startPrank(user);
        (bool success,) = address(vault).call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        // Get stETH by depositing ETH to Lido
        (success,) = MC.STETH.call{value: stethAmount}("");
        require(success, "stETH deposit failed");
        IERC20(MC.STETH).approve(address(vault), stethAmount);
        IERC20(MC.STETH).transfer(address(vault), stethAmount);
        vm.stopPrank();

        // Get curve pool for ETH/stETH
        ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        ICurvePool pool = ICurvePool(registry.find_pool_for_coins(MC.ETH, MC.STETH));

        // Prepare amounts array for add_liquidity
        uint256[2] memory amounts = [ethAmount, stethAmount];
        uint256 minLpOut = (pool.calc_token_amount(amounts, true) * 999) / 1000; // 0.1% slippage

        // Prepare add_liquidity data
        bytes memory addLiquidityData = abi.encodeWithSelector(
            bytes4(keccak256("add_liquidity(uint256[2],uint256)")),
            amounts,
            minLpOut
        );
        {
            address[] memory targets = new address[](2);
            targets[0] = MC.STETH;
            targets[1] = address(pool);

            uint256[] memory values = new uint256[](2);
            values[0] = 0;
            values[1] = ethAmount; // Send ETH with the call

            bytes[] memory callData = new bytes[](2);
            callData[0] = abi.encodeWithSignature("approve(address,uint256)", address(pool), stethAmount);
            callData[1] = addLiquidityData;

            vm.startPrank(PROCESSOR);
            vault.processor(targets, values, callData);
            vm.stopPrank();
        }

        // Assert ETH balance is reduced and LP tokens were received
        assertApproxEqAbs(address(vault).balance, 0, 2);
        assertApproxEqAbs(IERC20(MC.STETH).balanceOf(address(vault)), 0, 2);
        uint256 lpBalance = IERC20(pool.lp_token()).balanceOf(address(vault));
        assertGt(lpBalance, minLpOut);
    }
}
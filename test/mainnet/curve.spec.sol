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
import {console} from "lib/forge-std/src/console.sol";
import {IStETH} from "src/interface/external/lido/IStETH.sol";



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

    function testCurveSwap() public {
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

        // Exchange stETH for ETH via Curve pool
        ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        ICurvePool pool = ICurvePool(registry.find_pool_for_coins(MC.ETH, MC.STETH));

        console.log("Curve pool address:", address(pool));

        uint256 swapAmount = amount / 2;

        uint256 minOut = pool.get_dy(1, 0, swapAmount); // Swap from stETH (1) to ETH (0)

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
    }

}
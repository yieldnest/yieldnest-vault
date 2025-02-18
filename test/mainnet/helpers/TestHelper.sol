// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";
import {BaseVault} from "src/BaseVault.sol";
import {IynETH} from "test/interface/external/yieldnest/IynETH.sol";
import {IynEigen} from "test/interface/external/yieldnest/IynEigen.sol";
import {IWETH} from "test/interface/external/ethereum/IWETH.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IStETH} from "test/interface/external/lido/IStETH.sol";
import {IwstETH} from "test/interface/external/lido/IwstETH.sol";
import {IERC20} from "src/Common.sol";

contract TestHelper is Test {
    function dealAsset(address asset, address account, uint256 amount) internal returns (uint256) {
        if (asset == MC.OETH) {
            deal(MC.WETH, account, amount);

            vm.startPrank(account);
            IERC20(MC.WETH).approve(MC.OETH_VAULT, amount);
            IOETHVault(MC.OETH_VAULT).mint(MC.WETH, amount, amount);
            vm.stopPrank();
            return amount;
        }

        if (asset == MC.YNETH) {
            deal(account, amount);

            vm.startPrank(account);
            uint256 amount_ = IynETH(MC.YNETH).depositETH{value: amount}(account);
            vm.stopPrank();
            return amount_;
        }

        if (asset == MC.STETH) {
            deal(account, amount);

            vm.startPrank(account);
            IStETH(MC.STETH).submit{value: amount}(address(0));
            vm.stopPrank();

            return amount;
        }

        if (asset == MC.WSTETH) {
            amount = dealAsset(MC.STETH, account, amount);

            vm.startPrank(account);
            IERC20(MC.STETH).approve(MC.WSTETH, amount);
            uint256 amount_ = IwstETH(MC.WSTETH).wrap(amount);
            vm.stopPrank();

            return amount_;
        }

        if (asset == MC.YNLSDE) {
            amount = dealAsset(MC.WSTETH, account, amount);

            vm.startPrank(account);
            IERC20(MC.WSTETH).approve(MC.YNLSDE, amount);
            uint256 amount_ = IynEigen(MC.YNLSDE).deposit(MC.WSTETH, amount, account);
            vm.stopPrank();
            return amount_;
        }

        deal(asset, account, amount);

        return amount;
    }
}

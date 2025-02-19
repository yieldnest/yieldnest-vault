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
    BaseVault private _vault;

    function _initVault(BaseVault vault_) internal {
        _vault = vault_;
    }
    /// @notice Deals assets to an account by converting ETH to the desired asset
    /// @param asset The asset to deal
    /// @param account The account to receive the asset
    /// @param amount The amount of ETH to convert
    /// @return The actual amount of asset received after conversion
    function dealAsset(address asset, address account, uint256 amount) internal returns (uint256) {

        if (asset == MC.WETH) {
            deal(account, amount);

            vm.startPrank(account);
            IWETH(MC.WETH).deposit{value: amount}();
            vm.stopPrank();
            return amount;
        }

        if (asset == MC.OETH) {
            dealAsset(MC.WETH, account, amount);

            vm.startPrank(account);
            IERC20(MC.WETH).approve(MC.OETH_VAULT, amount);
            IOETHVault(MC.OETH_VAULT).mint(MC.WETH, amount, amount);
            vm.stopPrank();
            return amount;
        }

        if (asset == MC.WOETH) {
            amount = dealAsset(MC.OETH, account, amount);

            vm.startPrank(account);
            IERC20(MC.OETH).approve(MC.WOETH, amount);
            uint256 amount_ = IERC4626(MC.WOETH).deposit(amount, account);
            vm.stopPrank();
            return amount_;
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

    // used only for totalAssets invariance
    function customAssertEq(uint256 a, uint256 b, string memory message) private pure {
        if (a < 1e14) {
            // 1e4 in 1e18 is 0 for a < 1e14
            // threshold is 1 wei for a < 1e14
            assertApproxEqAbs(a, b, 1, message);
        } else if (a < 100 ether) {
            // 1e4 / 1e18 = 1e-14 (= 1e-12 percent)
            // 1e4 / 1e18 at 1e14 wei = 1 wei (lower bound)
            // 1e4 / 1e18 at 1e2 ether (or 1e20 wei) = 1e6 wei (higher bound)
            assertApproxEqRel(a, b, 1e4, message);
        } else {
            // threshold is 1e6 wei for a >= 1e2 ether
            assertApproxEqAbs(a, b, 1e6, message);
        }
    }

    function totalSupplyInvariant(uint256 supply) public view {
        assertTrue(address(_vault) != address(0));
        uint256 finalVaultTotalSupply = _vault.totalSupply();
        assertEq(supply, finalVaultTotalSupply, "Vault totalSupply should be original totalSupply plus additional");
    }

    function totalAssetsInvariant(uint256 assets) public view {
        assertTrue(address(_vault) != address(0));
        uint256 finalVaultTotalAssets = _vault.totalAssets();
        customAssertEq(
            assets, finalVaultTotalAssets, "Vault totalAssets should be original totalAssets plus additional"
        );
    }
}

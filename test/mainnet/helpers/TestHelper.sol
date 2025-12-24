// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {BaseVault} from "src/BaseVault.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";

contract TestHelper is Test, AssertUtils {
    BaseVault private _vault;

    function _initVault(BaseVault vault_) internal {
        _vault = vault_;
    }

    function dealAsset(address asset, address account, uint256 amount) internal returns (uint256) {
        if (asset == MC.SFRAX) {
            dealAsset(MC.FRAX, account, amount);

            vm.startPrank(account);
            IERC20(MC.FRAX).approve(MC.SFRAX, amount);
            IERC4626(MC.SFRAX).deposit(amount, account);
            vm.stopPrank();
            amount = IERC20(MC.SFRAX).balanceOf(account);
            return amount;
        }

        if (asset == MC.SUSDE) {
            dealAsset(MC.USDE, account, amount);

            vm.startPrank(account);
            IERC20(MC.USDE).approve(MC.SUSDE, amount);
            IERC4626(MC.SUSDE).deposit(amount, account);
            vm.stopPrank();
            amount = IERC20(MC.SUSDE).balanceOf(account);
            return amount;
        }

        if (asset == MC.SUSDS) {
            dealAsset(MC.USDS, account, amount);

            vm.startPrank(account);
            IERC20(MC.USDS).approve(MC.SUSDS, amount);
            IERC4626(MC.SUSDS).deposit(amount, account);
            vm.stopPrank();
            amount = IERC20(MC.SUSDS).balanceOf(account);
            return amount;
        }

        if (asset == MC.SCRVUSD) {
            dealAsset(MC.CRVUSD, account, amount);

            vm.startPrank(account);
            IERC20(MC.CRVUSD).approve(MC.SCRVUSD, amount);
            IERC4626(MC.SCRVUSD).deposit(amount, account);
            vm.stopPrank();
            amount = IERC20(MC.SCRVUSD).balanceOf(account);
            return amount;
        }

        deal(asset, account, amount);

        return amount;
    }

    // used only for totalAssets invariance
    function customAssertEq(uint256 a, uint256 b, string memory message) private pure {
        if (a < 1e14) {
            // 1e4 in 1e18 is 0 for a < 1e14
            // threshold is 2 wei for a < 1e14
            assertApproxEqAbs(a, b, 2, message);
        } else if (a < 100 ether) {
            // 2e4 / 1e18 = 1e-14 (= 2e-12 percent)
            // 2e4 / 1e18 at 1e14 wei = 2 wei (lower bound)
            // 2e4 / 1e18 at 1e2 ether (or 1e20 wei) = 2e6 wei (higher bound)
            assertApproxEqRel(a, b, 2e4, message);
        } else {
            // threshold is 2e6 wei for a >= 1e2 ether
            assertApproxEqAbs(a, b, 2e6, message);
        }
    }

    function dealMore(address receiver, uint256 amount) public {
        // First deal ETH to an intermediate address
        address intermediary = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
        deal(intermediary, amount);

        // Have intermediary send to final receiver
        vm.prank(intermediary);
        payable(receiver).transfer(amount);
    }

    function totalSupplyInvariant(uint256 expectedTotalSupply) public view {
        uint256 finalVaultTotalSupply = _vault.totalSupply();
        assertEqThreshold(
            finalVaultTotalSupply,
            expectedTotalSupply,
            10,
            "Vault totalSupply should be original totalSupply plus additional"
        );
    }

    function totalAssetsInvariant(uint256 expectedTotalAssets) public view {
        uint256 finalVaultTotalAssets = _vault.totalAssets();
        assertEqThreshold(
            expectedTotalAssets,
            finalVaultTotalAssets,
            10,
            "Vault totalAssets should be original totalAssets plus additional"
        );
    }
}

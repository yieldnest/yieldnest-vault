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

    function totalSupplyInvariant(uint256 supply) public view {
        assertTrue(address(_vault) != address(0));
        uint256 finalVaultTotalSupply = _vault.totalSupply();
        assertEq(supply, finalVaultTotalSupply, "Vault totalSupply should be original totalSupply plus additional");
    }

    function totalAssetsInvariant(uint256 supply) public view {
        totalAssetsInvariant(supply, "Vault totalAssets should be original totalAssets plus additional");
    }

    function totalAssetsInvariant(uint256 assets, string memory message) public view {
        assertTrue(address(_vault) != address(0));
        uint256 finalVaultTotalAssets = _vault.totalAssets();
        customAssertEq(assets, finalVaultTotalAssets, message);
    }

    function dealMore(address receiver, uint256 amount) public {
        // First deal ETH to an intermediate address
        address intermediary = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
        deal(intermediary, amount);

        // Have intermediary send to final receiver
        vm.prank(intermediary);
        payable(receiver).transfer(amount);
    }
}

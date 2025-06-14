// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IBNBXStakeManagerV2} from "src/interface/external/stader/IBNBXStakeManagerV2.sol";
import {ISlisBnbStakeManager} from "src/interface/external/lista/ISlisBnbStakeManager.sol";
import {IAsBnbMinter} from "src/interface/external/astherus/IAsBnbMinter.sol";
import {IVault} from "src/interface/IVault.sol";

interface IBaseStrategy {
    function STRATEGY_VERSION() external view returns (string memory);
}

/*
    The Provider fetches state from other contracts.
*/
contract Provider is IProvider {
    error UnsupportedAsset(address asset);

    function isBNBStrategyVault(address asset) public view returns (bool) {
        try IBaseStrategy(asset).STRATEGY_VERSION() returns (string memory version) {
            address vaultAsset = IVault(asset).asset();
            return (
                keccak256(bytes(version)) == keccak256(bytes("0.1.0"))
                    || keccak256(bytes(version)) == keccak256(bytes("0.2.0"))
            ) && vaultAsset == MC.WBNB;
        } catch {
            return false;
        }
    }

    function isClisBnbStrategyVault(address asset) public view returns (bool) {
        try IBaseStrategy(asset).STRATEGY_VERSION() returns (string memory version) {
            address vaultAsset = IVault(asset).asset();
            return keccak256(bytes(version)) == keccak256(bytes("0.2.0")) && vaultAsset == MC.SLISBNB;
        } catch {
            return false;
        }
    }

    function getRate(address asset) public view virtual override returns (uint256) {
        if (
            asset == MC.YNWBNBK || asset == MC.YNBNBK || asset == MC.YNCLISBNBK || asset == MC.YNASBNBK
                || asset == MC.EULER_EWBNB_6_VAULT
        ) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == MC.WBNB) {
            return 1e18;
        }

        if (asset == MC.BNBX) {
            return IBNBXStakeManagerV2(MC.BNBX_STAKE_MANAGER).convertBnbXToBnb(1e18);
        }

        if (asset == MC.SLISBNB) {
            return ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(1e18);
        }

        if (asset == MC.ASBNB) {
            return ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(
                IAsBnbMinter(MC.AS_BNB_MINTER).convertToTokens(1e18)
            );
        }

        if (isBNBStrategyVault(asset)) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (isClisBnbStrategyVault(asset)) {
            // base asset to clisBnbStrategy is SlisBnb
            uint256 slisBnbPerShare = IERC4626(asset).convertToAssets(1e18);
            // converts slisBnbPerShare to bnb
            return ISlisBnbStakeManager(MC.SLIS_BNB_STAKE_MANAGER).convertSnBnbToBnb(slisBnbPerShare);
        }

        revert UnsupportedAsset(asset);
    }
}

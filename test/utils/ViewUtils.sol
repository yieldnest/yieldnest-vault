// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Vm} from "lib/forge-std/src/Vm.sol";
import {IHooks} from "src/interface/IHooks.sol";
import {IVault} from "src/interface/IVault.sol";
import {IFeeHooks} from "src/interface/IFeeHooks.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20Metadata} from "src/Common.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

interface IMetaHooks {
    function getHooks() external view returns (IHooks[] memory);
}

library ViewUtils {
    using Math for uint256;

    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    error HooksNotFound();


    /**
     * @notice Returns the address of the fee hooks
     * @param vault The vault address
     * @return The address of the fee hooks
     */
    function getFeeHooks(IVault vault) internal view returns (address) {
        return getHooks(vault, "PerformanceFeeHooks");  
    }


    function getPerformanceFee(IVault vault) internal view returns (uint256) {
        return IFeeHooks(getFeeHooks(vault)).performanceFee();
    }

    function getHooks(IVault vault, string memory name) internal view returns (address) {
        IHooks hooks = IVault(vault).hooks();

        if (keccak256(abi.encodePacked(hooks.name())) == keccak256(abi.encodePacked(name))) {
            return address(hooks);
        }

        if (keccak256(abi.encodePacked(hooks.name())) == keccak256(abi.encodePacked("MetaHooks"))) {
            IMetaHooks metaHooks = IMetaHooks(address(hooks));
            IHooks[] memory metaHooksUnderlyingHooks = metaHooks.getHooks();
            for (uint256 i = 0; i < metaHooksUnderlyingHooks.length; i++) {
                if (keccak256(abi.encodePacked(metaHooksUnderlyingHooks[i].name())) == keccak256(abi.encodePacked(name))) {
                    return address(metaHooksUnderlyingHooks[i]);
                }
            }
        }

        revert HooksNotFound();
    }

    function getPerformanceFeeReceiverBalance(IVault vault) internal view returns (uint256) {
        address feeHooks = getFeeHooks(vault);
        return vault.balanceOf(IFeeHooks(feeHooks).performanceFeeRecipient());
    }

    function convertAssetToBase(IVault vault, address asset, uint256 amount) internal view returns (uint256) {
        uint256 rate = IProvider(vault.provider()).getRate(asset);
        uint256 baseAssets = amount.mulDiv(rate, 10 ** IERC20Metadata(asset).decimals(), Math.Rounding.Floor);
        return baseAssets;
    }
}
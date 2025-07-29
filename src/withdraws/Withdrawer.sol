// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseWithdrawer} from "src/withdraws/BaseWithdrawer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";

contract Withdrawer is BaseWithdrawer {
    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @param asset_ The address of the asset.
     * @return baseAssets The amount of base assets in the queue.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address asset_) public view virtual override returns (uint256 baseAssets) {
        if (asset_ == MC.FXBASE) {
            uint256 queuedFxBaseShares = IFxUSDBasePool(MC.FXBASE).redeemRequests(address(this)).amount;
            return _convertAssetToBase(MC.FXBASE, queuedFxBaseShares);
        }

        return 0;
    }
}

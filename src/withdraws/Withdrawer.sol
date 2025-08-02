// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseWithdrawer} from "src/withdraws/BaseWithdrawer.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";
import {console} from "lib/forge-std/src/console.sol";

contract Withdrawer is BaseWithdrawer {
    /**
     * @notice function to handle the assets that are in queue for withdrawal.
     * @return baseAssets The amount of base assets in the queue.
     * @dev This function should return the amount in base denomination.
     */
    function asyncWithdrawalBalance(address /* asset_ */ ) public view virtual override returns (uint256 baseAssets) {
        // When FXBASE signals requestRedeem for redemptions, the balance of FXBASE does not change
        // aka shares are not transferred or burned.

        return 0;
    }
}

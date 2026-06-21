// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {BaseWithdrawerMainnetTest} from "test/mainnet/BaseWithdrawerTest.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";

/**
 * @notice Tests for the Withdrawer contract deployed with ynETHx
 *
 */
contract WithdrawerMainnetTest is BaseWithdrawerMainnetTest {
    function getWithdrawer() public override returns (Withdrawer) {
        Withdrawer withdrawer = VaultVerification.getWithdrawer(vault);

        _initVault(withdrawer);
        return withdrawer;
    }

    /**
     * @notice Test to verify the version of the Withdrawer contract
     * @dev This test ensures that the deployed Withdrawer contract has the correct version
     */
    function test_check_withdrawer_version() public {
        Withdrawer withdrawer = getWithdrawer();

        // Assert that the Withdrawer contract has the correct version
        assertEq(withdrawer.STRATEGY_VERSION(), "0.2.0", "Withdrawer should have version 0.2.0");
    }
}

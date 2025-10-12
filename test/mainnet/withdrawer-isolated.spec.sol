// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {SetupWithdrawer} from "test/mainnet/helpers/SetupWithdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IERC20, Math} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IWithdrawalQueueManager, IRedemptionAssetsVault} from "src/interface/IWithdrawalQueueManager.sol";
import {IWithdrawalQueue} from "src/interface/external/lido/IWithdrawalQueue.sol";
import {IProvider} from "src/interface/IProvider.sol";

import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IOETHVault} from "src/interface/external/origin/IOETHVault.sol";
import {TestHelper} from "test/mainnet/helpers/TestHelper.sol";
import {OriginWithdrawalLib} from "src/withdraws/library/OriginWithdrawalLib.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {BaseWithdrawerMainnetTest} from "test/mainnet/BaseWithdrawerTest.sol";

/**
 * @notice Tests for the Withdrawer contract
 *
 * This test suite verifies the Withdrawer contract's functionality in isolation with a fresh deployment.
 * Unlike other test suites that test integration with the main vault, these tests focus solely on the
 * Withdrawer contract's core withdrawal functionality. By testing in isolation, we can verify the
 * withdrawal logic works correctly without any dependencies on the main vault's state or behavior.
 *
 */
contract WithdrawerIsolatedMainnetTest is BaseWithdrawerMainnetTest {
    function getWithdrawer() public override returns (Withdrawer) {
        SetupWithdrawer setup = new SetupWithdrawer();
        withdrawer = Withdrawer(setup.setup());
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
        assertEq(withdrawer.STRATEGY_VERSION(), "0.3.0", "Withdrawer should have version 0.3.0");
    }
}

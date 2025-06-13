// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {VerifyMaxVault} from "script/VerifyMaxVault.s.sol";
import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";

contract VaultMainnetUpgradeTest is BaseTest {
    function test_Vault_Verifier_verify() public {
        // Skipping verifier test until we have mainnet deployment
        vm.skip(true);
        VerifyMaxVault verifier = new VerifyMaxVault();
        verifier.setIsTestEnv(true);
        verifier.run();
    }
}

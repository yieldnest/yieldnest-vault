// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {VerifyMaxVault} from "script/VerifyMaxVault.s.sol";

contract VaultMainnetUpgradeTest {
    function test_Vault_Verifier_verify() public {
        VerifyMaxVault verifier = new VerifyMaxVault();
        verifier.setIsTestEnv(true);
        verifier.run();
    }
}

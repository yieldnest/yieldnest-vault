// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {BaseIntegrationTest} from "test/mainnet/BaseIntegrationTest.sol";
import {UpgradeUtils} from "test/utils/UpgradeUtils.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {VaultVerification} from "script/verification/VaultVerification.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {VerifyMaxVault} from "script/VerifyMaxVault.s.sol";

contract VaultMainnetUpgradeTest is BaseIntegrationTest {
    // Implementation addresses
    Vault public vaultImplementation;
    Withdrawer public withdrawerImplementation;

    function setUp() public override {
        super.setUp();
    }

    function test_Vault_Verifier_verify() public {
        VerifyMaxVault verifier = new VerifyMaxVault();
        verifier.setIsTestEnv(true);
        verifier.run();
    }
}
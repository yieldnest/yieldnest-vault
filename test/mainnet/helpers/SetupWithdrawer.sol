// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";

contract SetupWithdrawer is Test, MainnetActors, Etches {
    function setup() public returns (Withdrawer vault) {
        string memory name = "YieldNest Withdrawer";
        string memory symbol = "ynWithdrawer";

        Withdrawer vaultImplementation = new Withdrawer();

        // Deploy the proxy
        bytes memory initData =
            abi.encodeWithSelector(Withdrawer.initialize.selector, ADMIN, name, symbol, 18, true, true);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        vault = Withdrawer(payable(address(vaultProxy)));

        configureVault(vault);
    }

    function configureVault(Withdrawer vault) internal {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);

        // test cannot unpause vault without buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true, true);
        vault.addAsset(MC.STETH, true, true);
        vault.addAsset(MC.WSTETH, true, true);
        vault.addAsset(MC.METH, true, true);
        vault.addAsset(MC.RETH, true, true);
        vault.addAsset(MC.WOETH, true, true);
        vault.addAsset(MC.SWELL, true, true);
        vault.addAsset(MC.SFRXETH, true, true);
        vault.addAsset(MC.YNLSDE, true, true);
        vault.addAsset(MC.YNETH, true, true);
        // configure processor rules

        // TODO: add rules for withdraws

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract SetupWithdrawer is Test, Etches, MainnetActors {
    function setup() public returns (Withdrawer vault, WETH9 weth) {
        Withdrawer vaultImplementation = new Withdrawer();

        // Deploy the proxy
        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, "");

        vault = Withdrawer(payable(address(vaultProxy)));

        string memory name = "YieldNest Withdrawer";
        string memory symbol = "ynWithdrawer";
        uint8 decimals_ = 18;
        bool countNativeAsset_ = true;
        bool alwaysComputeTotalAssets_ = false;
        uint256 defaultAssetIndex = 0;

        vm.prank(ADMIN);
        vault.initialize(
            ADMIN, name, symbol, decimals_, countNativeAsset_, alwaysComputeTotalAssets_, defaultAssetIndex
        );
        weth = WETH9(payable(MC.WETH));

        configureLocal(vault);
    }

    function configureLocal(Withdrawer vault) internal {
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

        // test cannot unpause vault withtout buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true, true);
        vault.addAsset(MC.STETH, 18, true, true);
        vault.addAsset(MC.YNETH, true, true);

        // configure processor rules

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }
}

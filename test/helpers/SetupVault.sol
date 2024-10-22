// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {Vault} from "src/Vault.sol";
import {IRateProvider} from "src/interface/IRateProvider.sol";
import {ETHRateProvider, IERC20, TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {Etches} from "test/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";

contract SetupVault is Test, Etches, MainnetActors {
    function setup() public returns (Vault vault, WETH9 weth, ETHRateProvider rateProvider) {
        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";
        weth = WETH9(payable(WETH));
        rateProvider = new ETHRateProvider();

        Vault vaultImplementation = new Vault();

        // etch to mock the mainnet contracts address
        mockWETH9();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol);

        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(address(vaultProxy));

        vm.startPrank(ADMIN);
        // Set up the rate provider
        vault.setRateProvider(address(rateProvider));

        // Add WETH as an asset
        vault.addAsset(address(weth), 18);

        // Unpause the vault
        vault.pause(false);
        vm.stopPrank();
    }
}

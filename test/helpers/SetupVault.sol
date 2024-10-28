// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {Etches} from "test/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";

contract SetupVault is Test, Etches, MainnetActors {
    function setup() public returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";
        weth = WETH9(payable(WETH));

        Vault vaultImplementation = new Vault();

        // etch to mock the mainnet contracts
        mockAll();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol);

        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(address(vaultProxy));

        vm.startPrank(ADMIN);
        // Set up the rate provider
        vault.setRateProvider(address(ETH_RATE_PROVIDER));

        // Add assets: Base asset always first
        vault.addAsset(WETH, 18);
        vault.addAsset(STETH, 18);
        vault.addAsset(YNETH, 18);
        vault.addAsset(YNLSDE, 18);

        // Whitelist the approve function signature for the assets
        bytes4 approveSig = bytes4(keccak256("approve(address,uint256)"));
        vault.setWhitelist(WETH, approveSig);
        vault.setWhitelist(STETH, approveSig);
        vault.setWhitelist(YNETH, approveSig);
        vault.setWhitelist(YNLSDE, approveSig);

        // add strategies
        vault.addStrategy(BUFFER_STRATEGY, 18);
        vault.addStrategy(YNETH, 18);
        vault.addStrategy(YNLSDE, 18);

        // Whitelist Buffer Strategy functions
        bytes4 depositSig = bytes4(keccak256("deposit(uint256,address)"));
        bytes4 withdrawSig = bytes4(keccak256("withdraw(uint256,address,address)"));
        vault.setWhitelist(BUFFER_STRATEGY, depositSig);
        vault.setWhitelist(BUFFER_STRATEGY, withdrawSig);

        vault.setBufferStrategy(BUFFER_STRATEGY);

        // Unpause the vault
        vault.pause(false);
        vm.stopPrank();
    }
}

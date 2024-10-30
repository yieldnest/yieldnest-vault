// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IERC20} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {Etches} from "test/helpers/Etches.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupVault} from "test/helpers/SetupVault.sol";
import {MainnetActors} from "script/Actors.sol";
import {MockSTETH} from "test/mocks/MockST_ETH.sol";
import {IVault} from "src/interface/IVault.sol";

contract VaultDepositUnitTest is Test, MainnetContracts, MainnetActors, Etches {
    Vault public vaultImplementation;
    TransparentUpgradeableProxy public vaultProxy;

    Vault public vault;
    WETH9 public weth;
    MockSTETH public steth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 200_000 ether;

    function setUp() public {
        SetupVault setupVault = new SetupVault();
        (vault, weth) = setupVault.setup();

        // Replace the steth mock with our custom MockSTETH
        steth = MockSTETH(payable(STETH));

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(vault), type(uint256).max);
    }
}
// deposits 10 ETH to ynETH

// Also each strategy has potentially different deposit signature calls

// Eg.

// deposit(address. asset, uint256 amount, address receiver)
// deposit(uint256 amount, address receiver)
// or some other version.

// In the beginning the bytes calldata parameter was considered to inject custom calls with some guard rails around those.

// We'd have to have a way of doing that

// As discussed in the call, sounds like we'd want

// the strategy controller/governor to be able to call a limited set of transactions with whitelisted targets

// What does it mean for totalAssets during redemptions:
// Other things to consider here:

// Suppose we have strategies with asynchronous withdrawals:

// ynETH
// https://etherscan.io/address/0x0BC9BC81aD379810B36AD5cC95387112990AA67b

// Example: weETH (hypothetical)
// https://etherscan.io/address/0x7d5706f6ef3F89B3951E23e557CDFBC3239D4E2c

// What would be an approach to handle totalAssets assuming one of these positions is being unwinded?

// Since across withdrawal mechanisms a standard does not exist.

// Some may not use NFTs and simply positions so the behaviour is custom.

// How. can we code that behaviour to still measure totalAssets?

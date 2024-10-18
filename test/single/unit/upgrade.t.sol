// BSD 3-Clause License
pragma solidity ^0.8.24;

import {SingleVault} from "src/SingleVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {Etches} from "test/helpers/Etches.sol";
import {LocalActors} from "script/Actors.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {IERC20} from "src/Common.sol";
import {IVaultFactory} from "src/interface/IVaultFactory.sol";
import {MockSingleVault} from "test/mocks/MockSingleVault.sol";
import {TimelockController} from "src/Common.sol";

import "forge-std/Test.sol";

contract SingleVaultUpgradeTests is Test, LocalActors, TestConstants {
    SingleVault public vault;
    MockERC20 public asset;
    IVaultFactory public factory;

    function setUp() public {
        vm.startPrank(ADMIN);
        asset = MockERC20(address(new MockERC20(ASSET_NAME, ASSET_SYMBOL)));

        Etches etches = new Etches();
        etches.mockWETH9();

        SetupHelper setup = new SetupHelper();
        vault = setup.createVault();

        factory = IVaultFactory(setup.factory());
    }

    modifier onlyLocal() {
        if (block.chainid != 31337) return;
        _;
    }

    function testUpgrade() public onlyLocal {
        vm.startPrank(ADMIN);
        SingleVault newVault = new MockSingleVault();

        // the timelock on the factory is the admin for proxy upgrades
        TimelockController timelock = TimelockController(payable(factory.timelock()));

        // schedule a proxy upgrade transaction on the timelock
        // the traget is the proxy admin, created by foundry test
        address target = 0xF094c1B2ec3E52f6D02603C4dB28dd4Ba0067048;
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

        bytes memory data = abi.encodeWithSelector(selector, address(vault), address(newVault), "");

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");

        uint256 delay = 1;
        vm.startPrank(PROPOSER_1);
        timelock.schedule(target, value, data, predecessor, salt, delay);
        vm.stopPrank();

        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
        assert(timelock.getOperationState(id) == TimelockController.OperationState.Waiting);

        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);
        assertEq(timelock.isOperation(id), true);

        //execute the transaction
        vm.warp(500);
        vm.startPrank(EXECUTOR_1);
        timelock.execute(target, value, data, predecessor, salt);

        // Verify the transaction was executed successfully
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), true);
        assert(timelock.getOperationState(id) == TimelockController.OperationState.Done);
    }
}

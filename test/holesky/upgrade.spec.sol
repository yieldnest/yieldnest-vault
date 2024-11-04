// BSD 3-Clause License
pragma solidity ^0.8.24;

import {SingleVault} from "src/SingleVault.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {SetupHelper} from "test/helpers/Setup.sol";
import {IVaultFactory} from "src/interface/IVaultFactory.sol";
import {ISingleVault,SingleVault} from "src/SingleVault.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {HoleskyActors} from "script/Actors.sol";
import {HoleskyContracts} from "script/Contracts.sol";
import {Test} from "lib/forge-std/src/Test.sol";

contract SingleVaultUpgradeTests is Test, SetupHelper, HoleskyActors {
    SingleVault public vault;
    WETH9 public asset;

    function setUp() public {
        asset = WETH9(payable(WETH));
        vault = createVault();

        factory = IVaultFactory(factory);
    }

    modifier onlyHolesky() {
        if (block.chainid != 17000) return;
        _;
    }
    
    function test_Holesky_Vault_Upgrade() public onlyHolesky {
        deal(ADMIN, 100 ether);
        deal(PROPOSER_1, 100 ether);
        deal(EXECUTOR_1, 100 ether);

        vm.label(HoleskyContracts.TIMELOCK, "TIMELOCK");
        vm.label(HoleskyContracts.PROXY_ADMIN, "PROXY_ADMIN");
        vm.label(HoleskyContracts.YNETHX, "ynETHx");

        ISingleVault newVault = new SingleVault();

        // the timelock on the factory is the admin for proxy upgrades
        TLC timelock = TLC(payable(HoleskyContracts.TIMELOCK));

        // schedule a proxy upgrade transaction on the timelock
        // the traget is the proxy admin, Admin
        address target = HoleskyContracts.PROXY_ADMIN;
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

        bytes memory data = abi.encodeWithSelector(selector, HoleskyContracts.YNETHX, newVault, "");
      
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");

        uint256 delay = 10;
        vm.prank(PROPOSER_1);
        timelock.schedule(target, value, data, predecessor, salt, delay);

        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
        assert(timelock.getOperationState(id) == TLC.OperationState.Waiting);

        assertEq(timelock.isOperationReady(id), false); 
        assertEq(timelock.isOperationDone(id), false);
        assertEq(timelock.isOperation(id), true);

        //execute the transaction
        vm.warp(block.timestamp + 10);
        assertEq(timelock.isOperationReady(id), true);

        vm.prank(EXECUTOR_1);
        timelock.execute(target, value, data, predecessor, salt);

        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), true);
        assert(timelock.getOperationState(id) == TLC.OperationState.Done);
    }
}
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IActors, LocalActors} from "script/Actors.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IVaultFactory} from "src/IVaultFactory.sol";
import {IERC20} from "src/Common.sol";
import {TestConstants} from "test/helpers/Constants.sol";

contract SetupHelper is Test, LocalActors, TestConstants {
    IVaultFactory public factory;

    function createVault(IERC20 asset) public returns (SingleVault vault) {
        vm.startPrank(ADMIN);

        IActors actors = new LocalActors();

        address[] memory proposers = new address[](2);
        proposers[0] = PROPOSER_1;
        proposers[1] = PROPOSER_2;
        address[] memory executors = new address[](2);
        executors[0] = EXECUTOR_1;
        executors[1] = EXECUTOR_2;

        DeployVaultFactory factoryDeployer = new DeployVaultFactory();
        factory = IVaultFactory(factoryDeployer.deployVaultFactory(actors, 0));

        asset.approve(address(factory), 1 ether);
        asset.transfer(address(factory), 1 ether);
        address vaultAddress = factory.createSingleVault(
            asset,
            VAULT_NAME,
            VAULT_SYMBOL,
            ADMIN,
            0, // time delay
            proposers,
            executors
        );
        vault = SingleVault(payable(vaultAddress));
    }
}

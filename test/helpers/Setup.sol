pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IActors, LocalActors} from "script/Actors.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {DeployVaultFactory} from "script/Deploy.s.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IVaultFactory} from "src/interface/IVaultFactory.sol";
import {IERC20} from "src/Common.sol";
import {TestConstants} from "test/helpers/Constants.sol";
import {IWETH} from "src/interface/IWETH.sol";

contract SetupHelper is Test, LocalActors, TestConstants {
    IVaultFactory public factory;

    constructor() {
        IActors actors = new LocalActors();
        DeployVaultFactory factoryDeployer = new DeployVaultFactory();
        factory = IVaultFactory(factoryDeployer.deployVaultFactory(actors, 0, MainnetContracts.WETH));
    }

    function createVault() public returns (SingleVault vault) {
        vm.startPrank(ADMIN);

        deal(ADMIN, 100_000 ether);
        IWETH(payable(MainnetContracts.WETH)).deposit{value: 1 ether}();
        IERC20(MainnetContracts.WETH).transfer(address(factory), 1 ether);

        address vaultAddress = factory.createSingleVault(IERC20(MainnetContracts.WETH), VAULT_NAME, VAULT_SYMBOL, ADMIN);
        vault = SingleVault(payable(vaultAddress));
        vm.stopPrank();
    }
}

pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {IActors,HoleskyActors,MainnetActors} from "script/Actors.sol";
import {MainnetContracts,HoleskyContracts} from "script/Contracts.sol";
import {DeployFactory} from "script/DeployFactory.s.sol";
import {SingleVault} from "src/SingleVault.sol";
import {IVaultFactory} from "src/interface/IVaultFactory.sol";
import {IERC20} from "src/Common.sol";
import {Constants} from "script/Constants.sol";
import {IWETH} from "src/interface/IWETH.sol";
import {Etches} from "test/helpers/Etches.sol";

contract SetupHelper is Test, Etches, Constants {
    IVaultFactory public factory;
    IActors public actors;
    address public WETH;

    constructor() {
        if (block.chainid == 17000) {
            factory = IVaultFactory(HoleskyContracts.FACTORY);
            actors = new HoleskyActors();
            WETH = HoleskyContracts.WETH;
        } else if (block.chainid == 1) {
            WETH = MainnetContracts.WETH;
            actors = new MainnetActors();
            DeployFactory factoryDeployer = new DeployFactory();
            factory = IVaultFactory(factoryDeployer.deployVaultFactory(actors, 0, WETH));        
        } else {
            WETH = MainnetContracts.WETH;
            actors = new MainnetActors();
            DeployFactory factoryDeployer = new DeployFactory();
            factory = IVaultFactory(factoryDeployer.deployVaultFactory(actors, 0, WETH));      
        }
    }

    function createVault() public returns (SingleVault vault) {

        address ADMIN = actors.ADMIN();
        
        mockWETH9();

        deal(ADMIN, 100_000 ether);
        IWETH(payable(WETH)).deposit{value: 1 ether}();
        IERC20(WETH).transfer(address(factory), 1 ether);

        vm.prank(ADMIN);
        address vaultAddress = factory.createSingleVault(IERC20(WETH), VAULT_NAME, VAULT_SYMBOL, ADMIN);
        vault = SingleVault(payable(vaultAddress));
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupStrategy} from "test/mainnet/helpers/SetupStrategy.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {YNETHxLPStrategy} from "src/ynETHxLPStrategy.sol";
import {TokenizedStrategy} from "src/strategy/yearn/TokenizedStrategy.sol";

interface IynETH {
    function depositETH(address receiver) external payable returns (uint256);
    function balanceOf(address owner) external returns (uint256);
    function approve(address spender, uint256 amount) external returns (uint256);
}

contract VaultMainnetYnETHTest is Test, AssertUtils, MainnetActors {
    YNETHxLPStrategy public vault;
    TokenizedStrategy public tokenizedStrategy;
     address public buffer = address(0x45c3B59d53e2e148Aaa6a857521059676D5c0489);
    function setUp() public {
        SetupStrategy setup = new SetupStrategy();
        (tokenizedStrategy, vault) = setup.setup();
        vm.startPrank(ADMIN);
        configureMainnet();
        vm.stopPrank();
    }


    function configureMainnet() internal {
        // setApprovalRule(vault, MC.CURVE_LP_YNETH_YNLSDE_POOL, buffer);
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract SetupVault is Test, Etches, MainnetActors {
    function setup() public returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAx";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        vault = Vault(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));

        if (block.chainid == 31337) {
            configureLocal(vault);
        }

        if (block.chainid == 1) {
            configureMainnet(vault);
        }
    }

    function configureLocal(Vault vault) internal {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);

        // test cannot unpause vault withtout buffer
        vm.expectRevert();
        vault.pause(false);

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, 18);
        vault.addAsset(MC.STETH, 18);

        // configure processor rules
        setDepositRule(vault, MC.BUFFER_STRATEGY, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER_STRATEGY);
        setApprovalRule(vault, MC.WETH, MC.BUFFER_STRATEGY);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        // add strategies
        vault.addStrategy(MC.BUFFER_STRATEGY, 18);

        // test cannot unpause vault withtout buffer
        vm.expectRevert();
        vault.pause(false);
        vault.setBufferStrategy(MC.BUFFER_STRATEGY);

        // Unpause the vault
        vault.pause(false);
        vm.stopPrank();
    }

    function configureMainnet(Vault vault) internal {
        // etch to mock the mainnet contracts

        mockAll();

        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(payable(address(vaultProxy)));

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, 18);
        vault.addAsset(MC.STETH, 18);
        vault.addAsset(MC.YNETH, 18);
        vault.addAsset(MC.YNLSDE, 18);

        setDepositRule(vault, MC.BUFFER_STRATEGY, address(vault));
        setDepositRule(vault, MC.YNETH, address(vault));
        setDepositRule(vault, MC.YNLSDE, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER_STRATEGY);
        setApprovalRule(vault, MC.WETH, MC.BUFFER_STRATEGY);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        // add strategies
        vault.addStrategy(MC.BUFFER_STRATEGY, 18);
        vault.addStrategy(MC.YNETH, 18);
        vault.addStrategy(MC.YNLSDE, 18);

        vault.setBufferStrategy(MC.BUFFER_STRATEGY);

        // Unpause the vault
        vault.pause(false);
        vm.stopPrank();
    }

    function setDepositRule(Vault vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address spender) internal {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setWethDepositRule(Vault vault_, address weth_) public {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules});

        vault_.setProcessorRule(weth_, funcSig, rule);
    }
}

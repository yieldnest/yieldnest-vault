// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {ynETHxVault} from "src/ynETHxVault.sol";
import {IValidator} from "src/interface/IValidator.sol";


contract SetupVault is Test, MainnetActors, Etches {

    function upgrade() public {

        Vault newVault = Vault(payable(new ynETHxVault()));

        TLC timelock = TLC(payable(MC.TIMELOCK));

        // schedule a proxy upgrade transaction on the timelock
        // the traget is the proxy admin for the max Vault Proxy Contract
        address target = MC.PROXY_ADMIN;
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));
        
        bytes memory initData = abi.encodeWithSelector(ynETHxVault.initialize.selector, 18);
        bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(newVault), initData);

        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("chad");

        uint256 delay = 86400;

        vm.startPrank(PROPOSER_1);
        timelock.schedule(target, value, data, predecessor, salt, delay);
        vm.stopPrank();

        bytes32 id = keccak256(abi.encode(target, value, data, predecessor, salt));
        assert(timelock.getOperationState(id) == TLC.OperationState.Waiting);

        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), false);
        assertEq(timelock.isOperation(id), true);

        //execute the transaction
        vm.warp(block.timestamp + 86401);
        vm.startPrank(EXECUTOR_1);
        timelock.execute(target, value, data, predecessor, salt);

        // Verify the transaction was executed successfully
        assertEq(timelock.isOperationReady(id), false);
        assertEq(timelock.isOperationDone(id), true);
        assert(timelock.getOperationState(id) == TLC.OperationState.Done);

        vm.stopPrank();

        Vault vault = Vault(payable(MC.YNETHX));

        assertEq(vault.symbol(), "ynETHx");

        configureMainnet(vault);
    }

    function configureMainnet(Vault vault) internal {

        // etch to mock ETHRate provider and Buffer
        mockAll();

        vm.startPrank(ADMIN);
        
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, 18, true);
        vault.addAsset(MC.BUFFER, 18, false);
        vault.addAsset(MC.STETH, 18, true);
        vault.addAsset(MC.YNETH, 18, true);
        vault.addAsset(MC.YNLSDE, 18, true);

        setDepositRule(vault, MC.BUFFER, address(vault));
        setDepositRule(vault, MC.YNETH, address(vault));
        setDepositRule(vault, MC.YNLSDE, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER);
        setApprovalRule(vault, MC.WETH, MC.BUFFER);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        vault.setBuffer(MC.BUFFER);                                                                  
        
        vm.stopPrank();

        vault.processAccounting();
    }

    function setDepositRule(Vault vault_, address contractAddress, address receiver) public {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address spender) public {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;
        setApprovalRule(vault_, contractAddress, allowList);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address[] memory allowList) public {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setWethDepositRule(Vault vault_, address weth_) public {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(weth_, funcSig, rule);
    }    
}
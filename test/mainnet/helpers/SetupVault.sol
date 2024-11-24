// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TimelockController as TLC} from "src/Common.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {Etches} from "test/mainnet/helpers/Etches.sol";
import {ICurveRegistry} from "src/interface/external/curve/ICurveRegistry.sol";
import {ICurvePool} from "src/interface/external/curve/ICurvePool.sol";

contract SetupVault is Test, MainnetActors, Etches {

    function upgrade() public {

        Vault newVault = new Vault();

        TLC timelock = TLC(payable(MC.TIMELOCK));

        // schedule a proxy upgrade transaction on the timelock
        // the traget is the proxy admin for the max Vault Proxy Contract
        address target = MC.PROXY_ADMIN;
        uint256 value = 0;

        bytes4 selector = bytes4(keccak256("upgradeAndCall(address,address,bytes)"));

        bytes memory data = abi.encodeWithSelector(selector, MC.YNETHX, address(newVault), "");

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
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, 18);
        vault.addAsset(MC.STETH, 18);

        setDepositRule(vault, MC.BUFFER, address(vault));
        setDepositRule(vault, MC.YNETH, address(vault));
        setDepositRule(vault, MC.YNLSDE, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER);
        setApprovalRule(vault, MC.WETH, MC.BUFFER);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        // add strategies
        vault.addStrategy(MC.BUFFER, 18);
        vault.addStrategy(MC.YNETH, 18);
        vault.addStrategy(MC.YNLSDE, 18);

        vault.setBuffer(MC.BUFFER);     

        configureCurveActions(vault);                                                           

        // Unpause the vault
        vault.pause(false);
        vm.stopPrank();

        vault.processAccounting();
    }

    function configureCurveActions(Vault vault) internal {

        // Get ethSteth pool from registry
        ICurveRegistry registry = ICurveRegistry(MC.CURVE_REGISTRY);
        address ethStethPool = registry.find_pool_for_coins(MC.ETH, MC.STETH);

        // Add curve pools to array
        address[] memory curvePools = new address[](1);
        curvePools[0] = ethStethPool;

        // Add curve pool actions
        for (uint256 i = 0; i < curvePools.length; i++) {
            // Add liquidity functions
            bytes4 addLiq2 = bytes4(keccak256("add_liquidity(uint256[2],uint256)"));

            IVault.ParamRule[] memory addLiqRules = new IVault.ParamRule[](2);
            addLiqRules[0] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: true,
                allowList: new address[](0)
            });
            addLiqRules[1] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });

            vault.setProcessorRule(curvePools[i], addLiq2, IVault.FunctionRule({
                isActive: true,
                paramRules: addLiqRules
            }));

            // Exchange function
            bytes4 exchange = bytes4(keccak256("exchange(int128,int128,uint256,uint256)"));
            IVault.ParamRule[] memory exchangeRules = new IVault.ParamRule[](4);
            exchangeRules[0] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });
            exchangeRules[1] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });
            exchangeRules[2] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });
            exchangeRules[3] = IVault.ParamRule({
                paramType: IVault.ParamType.UINT256,
                isArray: false,
                allowList: new address[](0)
            });

            vault.setProcessorRule(curvePools[i], exchange, IVault.FunctionRule({
                isActive: true,
                paramRules: exchangeRules
            }));
        }
        // Set approval rule to allow ethStethPool to spend stETH tokens from the vault
        setApprovalRule(vault, MC.STETH, ethStethPool);
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
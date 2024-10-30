// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault, IVault} from "src/Vault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/mocks/MockWETH.sol";
import {Etches} from "test/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";

contract SetupVault is Test, Etches, MainnetActors {
    function setup() public returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";
        weth = WETH9(payable(WETH));

        Vault vaultImplementation = new Vault();

        // etch to mock the mainnet contracts
        mockAll();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol);

        TransparentUpgradeableProxy vaultProxy =
            new TransparentUpgradeableProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(address(vaultProxy));

        vm.startPrank(ADMIN);
        // Set up the rate provider
        vault.setRateProvider(address(ETH_RATE_PROVIDER));

        // Add assets: Base asset always first
        vault.addAsset(WETH, 18);
        vault.addAsset(STETH, 18);
        vault.addAsset(YNETH, 18);
        vault.addAsset(YNLSDE, 18);

        setWethDeposit(vault, WETH);

        setupProcessorRules(vault);

        // add strategies
        vault.addStrategy(BUFFER_STRATEGY, 18);
        vault.addStrategy(YNETH, 18);
        vault.addStrategy(YNLSDE, 18);

        vault.setBufferStrategy(BUFFER_STRATEGY);

        // Unpause the vault
        vault.pause(false);
        vm.stopPrank();
    }

    function setupProcessorRules(Vault vault_) internal {
        setDepositRule(vault_, BUFFER_STRATEGY, address(vault_));
        setDepositRule(vault_, YNETH, address(vault_));
        setDepositRule(vault_, YNLSDE, address(vault_));

        setApprovalRule(vault_, address(vault_), BUFFER_STRATEGY);
        setApprovalRule(vault_, WETH, BUFFER_STRATEGY);
        setApprovalRule(vault_, address(vault_), YNETH);
        setApprovalRule(vault_, address(vault_), YNLSDE);
    }

    function setDepositRule(Vault vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({
            paramType: IVault.ParamType.UINT256,
            minValue: bytes32(uint256(2)),
            maxValue: bytes32(uint256(100000 ether)),
            isArray: false,
            isRequired: true,
            allowList: new address[](0)
        });

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({
            paramType: IVault.ParamType.ADDRESS,
            minValue: bytes32(0),
            maxValue: bytes32(0),
            isArray: false,
            isRequired: true,
            allowList: allowList
        });

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, maxGas: 0});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address spender) internal {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        paramRules[0] = IVault.ParamRule({
            paramType: IVault.ParamType.ADDRESS,
            minValue: bytes32(0),
            maxValue: bytes32(0),
            isArray: false,
            isRequired: true,
            allowList: allowList
        });

        paramRules[1] = IVault.ParamRule({
            paramType: IVault.ParamType.UINT256,
            minValue: bytes32(0),
            maxValue: bytes32(type(uint256).max),
            isArray: false,
            isRequired: true,
            allowList: new address[](0)
        });

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, maxGas: 0});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setWethDeposit(Vault vault_, address weth_) public {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, maxGas: 0});

        vault_.setProcessorRule(weth_, funcSig, rule);
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";

contract SetupWithdrawer is Test, Etches, MainnetActors {
    function setup() public returns (Withdrawer vault, WETH9 weth) {
        string memory name = "YieldNest Withdrawer";
        string memory symbol = "ynWithdrawer";

        Withdrawer vaultImplementation = new Withdrawer();

        // Deploy the proxy
        bytes memory initData =
            abi.encodeWithSelector(Withdrawer.initialize.selector, ADMIN, name, symbol, 18, true, true);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        vault = Withdrawer(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));

        configureLocal(vault);
    }

    function configureLocal(Withdrawer vault) internal {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        vault.grantRole(vault.ALLOCATOR_ROLE(), MC.YNETHX);

        // test cannot unpause vault withtout buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true, true);
        vault.addAsset(MC.BUFFER, 18, false, false);
        vault.addAsset(MC.STETH, true, true);
        vault.addAsset(MC.WBTC, true, true);
        vault.addAsset(MC.METH, true, true);

        // configure processor rules
        setDepositRule(vault, MC.BUFFER, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, MC.WETH, MC.BUFFER);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        // TODO: add rules for withdraws

        vault.setBuffer(MC.BUFFER);

        // Set WBTC rate to 20 ETH
        MockProvider(MC.PROVIDER).setRate(MC.WBTC, 20e18);
        // Set METH rate to 1.2 ETH
        MockProvider(MC.PROVIDER).setRate(MC.METH, 1.2e18);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }

    function setDepositRule(Withdrawer vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setApprovalRule(Withdrawer vault_, address contractAddress, address spender) internal {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setWethDepositRule(Withdrawer vault_, address weth_) public {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(weth_, funcSig, rule);
    }
}

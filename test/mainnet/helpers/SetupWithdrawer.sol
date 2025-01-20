// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Withdrawer} from "src/withdraws/Withdrawer.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {IWithdrawalQueueManager, IRedemptionAssetsVault} from "src/interface/IWithdrawalQueueManager.sol";

contract SetupWithdrawer is Test, Etches, MainnetActors {
    IWithdrawalQueueManager public withdrawalQueueManagerLsde;
    IWithdrawalQueueManager public withdrawalQueueManagerYneth;
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

        withdrawalQueueManagerLsde = IWithdrawalQueueManager(payable(address(MC.YNLSDE_WM)));
        withdrawalQueueManagerYneth = IWithdrawalQueueManager(payable(address(MC.YNETH_WM)));
        configureWithdrawer(vault);
    }

    function configureWithdrawer(Withdrawer vault) internal {
        mockProvider();
        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);

        // test cannot unpause vault without buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsyncAsset(MC.YNLSDE, MC.YNLSDE_WM, true, true);
        vault.addAsyncAsset(MC.YNETH, MC.YNETH_WM, true, true);
        // configure processor rules

        //donate to redemtion asset vault
        address redemptionAssetsVaultLsde = address(withdrawalQueueManagerLsde.redemptionAssetsVault());
        address redemptionAssetsVaultYneth = address(withdrawalQueueManagerYneth.redemptionAssetsVault());

        deal(MC.YNLSDE, redemptionAssetsVaultLsde, 100 ether);
        deal(MC.YNETH, redemptionAssetsVaultYneth, 100 ether);
        // TODO: add rules for withdraws
        addApprovalRule(vault, MC.YNLSDE, MC.YNLSDE_WM);
        addApprovalRule(vault, MC.YNETH, MC.YNETH_WM);

        addAsyncWithdrawRule(vault, MC.YNLSDE_WM);
        addAsyncWithdrawRule(vault, MC.YNETH_WM);

        addClaimWithdrawalRule(vault, MC.YNLSDE_WM, ADMIN);
        addClaimWithdrawalRule(vault, MC.YNETH_WM, ADMIN);

        addClaimWithdrawalsRule(vault, MC.YNLSDE_WM, ADMIN);
        addClaimWithdrawalsRule(vault, MC.YNETH_WM, ADMIN);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }

    function addApprovalRule(Withdrawer vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});
        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function addAsyncWithdrawRule(Withdrawer vault_, address contractAddress) internal {
        bytes4 funcSig = bytes4(keccak256("requestWithdrawal(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function addClaimWithdrawalRule(Withdrawer vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("claimWithdrawal(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function addClaimWithdrawalsRule(Withdrawer vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("claimWithdrawals(uint256[],address[])"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: true, allowList: new address[](0)});

         address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: true, allowList: allowList});

        IVault.FunctionRule memory rule = IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }
}

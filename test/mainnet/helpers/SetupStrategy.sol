 // SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {TokenizedStrategy} from "src/strategy/yearn/TokenizedStrategy.sol";
import {YNETHxLPStrategy} from "src/ynETHxLPStrategy.sol";
contract SetupStrategy is Test, Etches, MainnetActors {
    // yearn Vault factory address for v3.0.2
   address public factory = 0x444045c5C13C246e117eD36437303cac8E250aB0;
 function setup() public returns (TokenizedStrategy tokenizedStrategy, YNETHxLPStrategy vault) {
        string memory name = "YieldNest-Curve LP";
        string memory symbol = "ynLPx";

        tokenizedStrategy = new TokenizedStrategy(factory);
        vault = new YNETHxLPStrategy(MC.CURVE_LP_YNETH_YNLSDE_POOL, name);
   
        vm.prank(ADMIN);
        

    }

    // function configureLPStrategy(Strategy vault) internal {
    //     // etch to mock the mainnet contracts
    //     string memory name = "YieldNest-Curve LP";
    //     string memory symbol = "ynETHxLP";

    //     vm.startPrank(ADMIN);

    //     vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
    //     vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
    //     vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
    //     vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
    //     vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
    //     vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
    //     vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

    //     vault.setProvider(MC.PROVIDER);

    //     // Add assets: Base asset always first
    //     vault.addAsset(MC.CURVE_LP_YNETH_YNLSDE_POOL, false);
    //     vault.addAsset(MC.YNETH, true);
    //     vault.addAsset(MC.YNLSDE, true);

    //     // configure processor rules
    //     // setDepositRule(vault, MC.BUFFER, address(vault));
    //     // setWethDepositRule(vault, MC.WETH);

    //     // setApprovalRule(vault, address(vault), MC.YNETH);
    //     // setApprovalRule(vault, address(vault), MC.YNLSDE);

    //     // setWithdrawRule(vault, MC.CURVE_LP_YNETH_YNLSDE_POOL, address(vault));

    //     vault.setBuffer(MC.BUFFER);

    //     // Unpause the vault
    //     vault.unpause();
    //     vm.stopPrank();
    // }

    function setDepositRule(Vault vault_, address contractAddress, address receiver) internal {
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

    function setApprovalRule(Vault vault_, address contractAddress, address spender) internal {
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

    function setWethDepositRule(Vault vault_, address weth_) public {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(weth_, funcSig, rule);
    }
}
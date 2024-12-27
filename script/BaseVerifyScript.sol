// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IVault} from "src/BaseVault.sol";
import {Vault} from "src/Vault.sol";
import {IValidator} from "src/interface/IVault.sol";
import {BaseScript} from "script/BaseScript.sol";
import {ProxyUtils} from "script/ProxyUtils.sol";

import {Test} from "lib/forge-std/src/Test.sol";

import {BaseVaultViewer} from "src/utils/BaseVaultViewer.sol";
import {console} from "lib/forge-std/src/console.sol";

abstract contract BaseVerifyScript is BaseScript, Test {
    function _verifyDefaultRoles() internal view virtual {
        // verify timelock roles
        console.log("Timelock:", address(timelock));
        {
            bool hasProviderRole = vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), address(timelock));
            console.log(hasProviderRole ? "\u2705" : "\u274C", "Timelock has PROVIDER_MANAGER_ROLE");
            assertEq(hasProviderRole, true);

            bool hasAssetRole = vault.hasRole(vault.ASSET_MANAGER_ROLE(), address(timelock));
            console.log(hasAssetRole ? "\u2705" : "\u274C", "Timelock has ASSET_MANAGER_ROLE");
            assertEq(hasAssetRole, true);

            bool hasBufferRole = vault.hasRole(vault.BUFFER_MANAGER_ROLE(), address(timelock));
            console.log(hasBufferRole ? "\u2705" : "\u274C", "Timelock has BUFFER_MANAGER_ROLE");
            assertEq(hasBufferRole, true);

            bool hasProcessorRole = vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), address(timelock));
            console.log(hasProcessorRole ? "\u2705" : "\u274C", "Timelock has PROCESSOR_MANAGER_ROLE");
            assertEq(hasProcessorRole, true);

            bool hasFeeRole = vault.hasRole(vault.FEE_MANAGER_ROLE(), address(timelock));
            console.log(hasFeeRole ? "\u2705" : "\u274C", "Timelock has FEE_MANAGER_ROLE");
            assertEq(hasFeeRole, true);
        }

        // verify actors roles
        {
            bool hasAdminRole = vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
            console.log(hasAdminRole ? "\u2705" : "\u274C", "Admin has DEFAULT_ADMIN_ROLE:", actors.ADMIN());
            assertEq(hasAdminRole, true);

            bool hasProcessorRole = vault.hasRole(vault.PROCESSOR_ROLE(), actors.PROCESSOR());
            console.log(hasProcessorRole ? "\u2705" : "\u274C", "Processor has PROCESSOR_ROLE:", actors.PROCESSOR());
            assertEq(hasProcessorRole, true);

            bool hasPauserRole = vault.hasRole(vault.PAUSER_ROLE(), actors.PAUSER());
            console.log(hasPauserRole ? "\u2705" : "\u274C", "Pauser has PAUSER_ROLE:", actors.PAUSER());
            assertEq(hasPauserRole, true);

            bool hasUnpauserRole = vault.hasRole(vault.UNPAUSER_ROLE(), actors.UNPAUSER());
            console.log(hasUnpauserRole ? "\u2705" : "\u274C", "Unpauser has UNPAUSER_ROLE:", actors.UNPAUSER());
            assertEq(hasUnpauserRole, true);
        }

        {
            // verify proxy roles
            bool hasVaultProxyAdmin = ProxyUtils.getProxyAdmin(address(vault)) == vaultProxyAdmin;
            console.log(hasVaultProxyAdmin ? "\u2705" : "\u274C", "Vault proxy admin is correct:", vaultProxyAdmin);
            assertEq(ProxyUtils.getProxyAdmin(address(vault)), vaultProxyAdmin);

            bool hasTimelockOwner = Ownable(ProxyUtils.getProxyAdmin(address(vault))).owner() == address(timelock);
            console.log(
                hasTimelockOwner ? "\u2705" : "\u274C", "Vault proxy admin owner is timelock:", address(timelock)
            );
            assertEq(Ownable(ProxyUtils.getProxyAdmin(address(vault))).owner(), address(timelock));
        }

        {
            // verify viewer roles
            bool hasViewerProxyAdmin = ProxyUtils.getProxyAdmin(address(viewer)) == viewerProxyAdmin;
            console.log(hasViewerProxyAdmin ? "\u2705" : "\u274C", "Viewer proxy admin is correct:", viewerProxyAdmin);
            assertEq(ProxyUtils.getProxyAdmin(address(viewer)), viewerProxyAdmin);

            bool hasAdminOwner = Ownable(ProxyUtils.getProxyAdmin(address(viewer))).owner() == actors.ADMIN();
            console.log(hasAdminOwner ? "\u2705" : "\u274C", "Viewer proxy admin owner is admin:", actors.ADMIN());
            assertEq(Ownable(ProxyUtils.getProxyAdmin(address(viewer))).owner(), actors.ADMIN());
        }

        {
            // verify timelock roles
            bool hasMinDelay = timelock.getMinDelay() == minDelay;
            console.log(hasMinDelay ? "\u2705" : "\u274C", "Timelock min delay is correct:", minDelay);
            assertEq(timelock.getMinDelay(), minDelay);

            bool hasProposer1 = timelock.hasRole(timelock.PROPOSER_ROLE(), actors.PROPOSER_1());
            console.log(hasProposer1 ? "\u2705" : "\u274C", "Proposer 1 has PROPOSER_ROLE:", actors.PROPOSER_1());
            assertEq(hasProposer1, true);

            bool hasProposer2 = timelock.hasRole(timelock.PROPOSER_ROLE(), actors.PROPOSER_2());
            console.log(hasProposer2 ? "\u2705" : "\u274C", "Proposer 2 has PROPOSER_ROLE:", actors.PROPOSER_2());
            assertEq(hasProposer2, true);

            bool hasExecutor1 = timelock.hasRole(timelock.EXECUTOR_ROLE(), actors.EXECUTOR_1());
            console.log(hasExecutor1 ? "\u2705" : "\u274C", "Executor 1 has EXECUTOR_ROLE:", actors.EXECUTOR_1());
            assertEq(hasExecutor1, true);

            bool hasExecutor2 = timelock.hasRole(timelock.EXECUTOR_ROLE(), actors.EXECUTOR_2());
            console.log(hasExecutor2 ? "\u2705" : "\u274C", "Executor 2 has EXECUTOR_ROLE:", actors.EXECUTOR_2());
            assertEq(hasExecutor2, true);

            bool hasAdmin = timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), actors.ADMIN());
            console.log(hasAdmin ? "\u2705" : "\u274C", "Admin has DEFAULT_ADMIN_ROLE:", actors.ADMIN());
            assertEq(hasAdmin, true);
        }
    }

    function _verifyTemporaryRoles() internal view virtual {
        assertEq(vault.hasRole(vault.PROVIDER_MANAGER_ROLE(), deployer), false);
        assertEq(vault.hasRole(vault.ASSET_MANAGER_ROLE(), deployer), false);
        assertEq(vault.hasRole(vault.BUFFER_MANAGER_ROLE(), deployer), false);
        assertEq(vault.hasRole(vault.PROCESSOR_MANAGER_ROLE(), deployer), false);

        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), deployer), false);
        assertEq(vault.hasRole(vault.PROCESSOR_ROLE(), deployer), false);
        assertEq(vault.hasRole(vault.PAUSER_ROLE(), deployer), false);
        assertEq(vault.hasRole(vault.UNPAUSER_ROLE(), deployer), false);
    }

    function _verifyViewer() internal view virtual {
        assertEq(address(viewer.getVault()), address(vault));
        BaseVaultViewer.AssetInfo[] memory assets = viewer.getAssets();
        address[] memory assertsList = vault.getAssets();
        assertEq(assets.length, assertsList.length);

        for (uint256 i = 0; i < assets.length; i++) {
            assertEq(assets[i].asset, assertsList[i]);
            assertEq(assets[i].canDeposit, vault.getAsset(assertsList[i]).active);
        }
    }

    function _verifyDepositRule(IVault vault_, address contractAddress) internal view {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyDepositAssetRule(IVault vault_, address contractAddress, address asset) internal view {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        _verifyDepositAssetRule(vault_, contractAddress, allowList);
    }

    function _verifyDepositAssetRule(IVault vault_, address contractAddress, address[] memory allowList)
        internal
        view
    {
        bytes4 funcSig = bytes4(keccak256("depositAsset(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowListReceivers = new address[](1);
        allowListReceivers[0] = address(vault_);

        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowListReceivers});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyWithdrawRule(IVault vault_, address contractAddress) internal view {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);

        bytes4 funcSig = bytes4(keccak256("withdraw(uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyWithdrawAssetRule(IVault vault_, address contractAddress, address asset) internal view {
        address[] memory allowList = new address[](1);
        allowList[0] = asset;

        _verifyWithdrawAssetRule(vault_, contractAddress, allowList);
    }

    function _verifyWithdrawAssetRule(IVault vault_, address contractAddress, address[] memory assetList)
        internal
        view
    {
        address[] memory allowList = new address[](1);
        allowList[0] = address(vault_);
        bytes4 funcSig = bytes4(keccak256("withdrawAsset(address,uint256,address,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[3] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyApprovalRule(IVault vault_, address contractAddress, address spender) internal view {
        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        _verifyApprovalRule(vault_, contractAddress, allowList);
    }

    function _verifyApprovalRule(IVault vault_, address contractAddress, address[] memory allowList) internal view {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, contractAddress, funcSig, rule);
    }

    function _verifyWethDepositRule(IVault vault_, address weth_) internal view {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, weth_, funcSig, rule);
    }

    function _verifyWethWithdrawRule(IVault vault_, address weth_) internal view {
        bytes4 funcSig = bytes4(keccak256("withdraw(uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        _verifyProcessorRule(vault_, weth_, funcSig, rule);
    }

    function _verifyProcessorRule(
        IVault vault_,
        address contractAddress,
        bytes4 funcSig,
        IVault.FunctionRule memory expectedResult
    ) internal view {
        IVault.FunctionRule memory rule = vault_.getProcessorRule(contractAddress, funcSig);

        // Add assertions
        assertEq(rule.isActive, expectedResult.isActive, "isActive does not match");
        assertEq(rule.paramRules.length, expectedResult.paramRules.length, "paramRules length does not match");

        for (uint256 i = 0; i < rule.paramRules.length; i++) {
            assertEq(
                uint256(rule.paramRules[i].paramType),
                uint256(expectedResult.paramRules[i].paramType),
                "paramType does not match"
            );
            assertEq(rule.paramRules[i].isArray, expectedResult.paramRules[i].isArray, "isArray does not match");
            assertEq(
                rule.paramRules[i].allowList.length,
                expectedResult.paramRules[i].allowList.length,
                "allowList length does not match"
            );

            for (uint256 j = 0; j < rule.paramRules[i].allowList.length; j++) {
                assertEq(
                    rule.paramRules[i].allowList[j],
                    expectedResult.paramRules[i].allowList[j],
                    "allowList element does not match"
                );
            }
        }
    }
}

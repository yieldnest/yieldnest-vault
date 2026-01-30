// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "./SafeRules.sol";

/**
 * @title AaveV3Rules
 * @notice Library for creating processor rules for Aave V3 Pool interactions
 * @dev These rules allow the vault to supply collateral, borrow, repay, and withdraw from Aave V3
 */
library AaveV3Rules {
    /**
     * @notice Creates a processor rule for Aave V3 supply function
     * @dev supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
     * @param aavePool The Aave V3 Pool address
     * @param assets Array of allowed assets to supply (e.g., [wstETH, stETH])
     * @param vault The vault address that will receive the aTokens
     * @return SafeRules.RuleParams The processor rule parameters
     */
    function getSupplyRule(address aavePool, address[] memory assets, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("supply(address,uint256,address,uint16)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        // Param 0: asset - whitelist allowed collateral assets
        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});

        // Param 1: amount - no restriction
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 2: onBehalfOf - must be the vault
        address[] memory vaultAllowList = new address[](1);
        vaultAllowList[0] = vault;
        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: vaultAllowList});

        // Param 3: referralCode - no restriction (uint16 treated as UINT256)
        paramRules[3] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: aavePool, funcSig: funcSig, rule: rule});
    }

    /**
     * @notice Creates a processor rule for Aave V3 supply function with single asset
     * @param aavePool The Aave V3 Pool address
     * @param asset The allowed asset to supply
     * @param vault The vault address
     * @return SafeRules.RuleParams The processor rule parameters
     */
    function getSupplyRule(address aavePool, address asset, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        return getSupplyRule(aavePool, assets, vault);
    }

    /**
     * @notice Creates a processor rule for Aave V3 withdraw function
     * @dev withdraw(address asset, uint256 amount, address to)
     * @param aavePool The Aave V3 Pool address
     * @param assets Array of allowed assets to withdraw
     * @param vault The vault address that will receive withdrawn assets
     * @return SafeRules.RuleParams The processor rule parameters
     */
    function getWithdrawRule(address aavePool, address[] memory assets, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("withdraw(address,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        // Param 0: asset - whitelist allowed assets
        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});

        // Param 1: amount - no restriction
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 2: to - must be the vault
        address[] memory vaultAllowList = new address[](1);
        vaultAllowList[0] = vault;
        paramRules[2] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: vaultAllowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: aavePool, funcSig: funcSig, rule: rule});
    }

    /**
     * @notice Creates a processor rule for Aave V3 withdraw function with single asset
     */
    function getWithdrawRule(address aavePool, address asset, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        return getWithdrawRule(aavePool, assets, vault);
    }

    /**
     * @notice Creates a processor rule for Aave V3 borrow function
     * @dev borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
     * @param aavePool The Aave V3 Pool address
     * @param assets Array of allowed assets to borrow (e.g., [USDC, USDT])
     * @param vault The vault address that will receive borrowed assets
     * @return SafeRules.RuleParams The processor rule parameters
     */
    function getBorrowRule(address aavePool, address[] memory assets, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("borrow(address,uint256,uint256,uint16,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](5);

        // Param 0: asset - whitelist allowed borrow assets
        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});

        // Param 1: amount - no restriction
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 2: interestRateMode - no restriction (1 = stable, 2 = variable)
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 3: referralCode - no restriction
        paramRules[3] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 4: onBehalfOf - must be the vault
        address[] memory vaultAllowList = new address[](1);
        vaultAllowList[0] = vault;
        paramRules[4] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: vaultAllowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: aavePool, funcSig: funcSig, rule: rule});
    }

    /**
     * @notice Creates a processor rule for Aave V3 borrow function with single asset
     */
    function getBorrowRule(address aavePool, address asset, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        return getBorrowRule(aavePool, assets, vault);
    }

    /**
     * @notice Creates a processor rule for Aave V3 repay function
     * @dev repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
     * @param aavePool The Aave V3 Pool address
     * @param assets Array of allowed assets to repay
     * @param vault The vault address repaying the debt
     * @return SafeRules.RuleParams The processor rule parameters
     */
    function getRepayRule(address aavePool, address[] memory assets, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        bytes4 funcSig = bytes4(keccak256("repay(address,uint256,uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);

        // Param 0: asset - whitelist allowed repay assets
        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assets});

        // Param 1: amount - no restriction
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 2: interestRateMode - no restriction
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Param 3: onBehalfOf - must be the vault
        address[] memory vaultAllowList = new address[](1);
        vaultAllowList[0] = vault;
        paramRules[3] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: vaultAllowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: aavePool, funcSig: funcSig, rule: rule});
    }

    /**
     * @notice Creates a processor rule for Aave V3 repay function with single asset
     */
    function getRepayRule(address aavePool, address asset, address vault)
        internal
        pure
        returns (SafeRules.RuleParams memory)
    {
        address[] memory assets = new address[](1);
        assets[0] = asset;
        return getRepayRule(aavePool, assets, vault);
    }

    /**
     * @notice Creates a processor rule for Aave V3 setUserEMode function
     * @dev setUserEMode(uint8 categoryId)
     * @param aavePool The Aave V3 Pool address
     * @return SafeRules.RuleParams The processor rule parameters
     */
    function getSetUserEModeRule(address aavePool) internal pure returns (SafeRules.RuleParams memory) {
        bytes4 funcSig = bytes4(keccak256("setUserEMode(uint8)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](1);

        // Param 0: categoryId - no restriction
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        return SafeRules.RuleParams({contractAddress: aavePool, funcSig: funcSig, rule: rule});
    }
}

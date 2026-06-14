// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault, IValidator} from "src/interface/IVault.sol";
import {SafeRules} from "script/rules/SafeRules.sol";

interface IAaveV3Pool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

contract AaveV3IntegrationTest is BaseTest {
    Vault public vault;
    Provider public provider;

    function setUp() public {
        (vault, provider) = BaseTest.deploy();
        vm.stopPrank();

        if (!vault.hasAsset(MC.AAVE_ETHEREUM_USDC)) {
            vm.prank(TIMELOCK);
            vault.addAsset(MC.AAVE_ETHEREUM_USDC, false);
        }

        Provider newProvider = new Provider(address(wrappedUSDC));
        vm.prank(TIMELOCK);
        vault.setProvider(address(newProvider));
        provider = newProvider;

        _configureAaveRules();
    }

    function _configureAaveRules() internal {
        SafeRules.RuleParams[] memory rules = new SafeRules.RuleParams[](3);

        // approve USDC spending by Aave pool
        address[] memory spenders = new address[](1);
        spenders[0] = MC.AAVE_V3_POOL;
        {
            bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));
            IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);
            paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: spenders});
            paramRules[1] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
            rules[0] = SafeRules.RuleParams({
                contractAddress: MC.USDC,
                funcSig: funcSig,
                rule: IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))})
            });
        }

        // AAVE pool.supply(asset, amount, onBehalfOf, referralCode)
        address[] memory assetAllow = new address[](1);
        assetAllow[0] = MC.USDC;
        address[] memory onBehalfAllow = new address[](1);
        onBehalfAllow[0] = address(vault);
        {
            bytes4 funcSig = bytes4(keccak256("supply(address,uint256,address,uint16)"));
            IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](4);
            paramRules[0] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetAllow});
            paramRules[1] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
            paramRules[2] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: onBehalfAllow});
            paramRules[3] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
            rules[1] = SafeRules.RuleParams({
                contractAddress: MC.AAVE_V3_POOL,
                funcSig: funcSig,
                rule: IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))})
            });
        }

        // AAVE pool.withdraw(asset, amount, to)
        {
            bytes4 funcSig = bytes4(keccak256("withdraw(address,uint256,address)"));
            IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);
            paramRules[0] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: assetAllow});
            paramRules[1] =
                IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
            paramRules[2] =
                IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: onBehalfAllow});
            rules[2] = SafeRules.RuleParams({
                contractAddress: MC.AAVE_V3_POOL,
                funcSig: funcSig,
                rule: IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))})
            });
        }

        vm.startPrank(ADMIN);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(this));
        vm.stopPrank();

        SafeRules.setProcessorRules(vault, rules, true);
    }

    function test_deposit_and_withdraw_aave_usdc() public {
        uint256 depositAmount = 100_000 * 1e6;

        address alice = makeAddr("alice");
        deal(MC.USDC, alice, depositAmount);

        vm.startPrank(alice);
        IERC20(MC.USDC).approve(address(vault), depositAmount);
        vault.depositAsset(MC.USDC, depositAmount, alice);
        vm.stopPrank();

        uint256 usdcVaultBefore = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 aUsdcVaultBefore = IERC20(MC.AAVE_ETHEREUM_USDC).balanceOf(address(vault));
        uint256 totalAssetsBefore = vault.totalAssets();

        _aaveSupply(depositAmount);
        vault.processAccounting();

        assertEq(
            IERC20(MC.USDC).balanceOf(address(vault)),
            usdcVaultBefore - depositAmount,
            "Vault USDC should decrease by supplied amount"
        );
        assertApproxEqAbs(
            IERC20(MC.AAVE_ETHEREUM_USDC).balanceOf(address(vault)) - aUsdcVaultBefore,
            depositAmount,
            2,
            "Vault aUSDC should equal supplied amount"
        );
        assertApproxEqAbs(
            vault.totalAssets(), totalAssetsBefore, 2, "Total assets should be unchanged after Aave supply"
        );

        uint256 usdcVaultBeforeWithdraw = IERC20(MC.USDC).balanceOf(address(vault));
        uint256 aUsdcBalance = IERC20(MC.AAVE_ETHEREUM_USDC).balanceOf(address(vault));

        _aaveWithdraw(aUsdcBalance);
        vault.processAccounting();

        assertApproxEqAbs(
            IERC20(MC.USDC).balanceOf(address(vault)) - usdcVaultBeforeWithdraw,
            aUsdcBalance,
            1,
            "Vault USDC should return after Aave withdraw"
        );
        assertLe(
            IERC20(MC.AAVE_ETHEREUM_USDC).balanceOf(address(vault)),
            aUsdcVaultBefore + 1,
            "Vault aUSDC should be drained back to starting balance"
        );
        assertApproxEqAbs(
            vault.totalAssets(), totalAssetsBefore, 1, "Total assets should be unchanged after Aave withdraw"
        );
    }

    function _aaveSupply(uint256 amount) internal {
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = MC.USDC;
        data[0] = abi.encodeCall(IERC20.approve, (MC.AAVE_V3_POOL, amount));

        targets[1] = MC.AAVE_V3_POOL;
        data[1] = abi.encodeCall(IAaveV3Pool.supply, (MC.USDC, amount, address(vault), 0));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }

    function _aaveWithdraw(uint256 amount) internal {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = MC.AAVE_V3_POOL;
        data[0] = abi.encodeCall(IAaveV3Pool.withdraw, (MC.USDC, amount, address(vault)));

        vm.prank(PROCESSOR);
        vault.processor(targets, values, data);
    }
}

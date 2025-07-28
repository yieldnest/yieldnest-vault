// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {SetupVault} from "test/unit/helpers/SetupVault.sol";
import {Vault} from "src/Vault.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {MockERC20} from "test/unit/mocks/MockERC20.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {Mock6DecimalsProvider} from "test/unit/mocks/Mock6DecimalsProvider.sol";
import {MockSwapper} from "test/unit/mocks/MockSwapper.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BaseRules} from "script/rules/BaseRules.sol";
import {SafeRules} from "script/rules/SafeRules.sol";
import {WrappedToken} from "lib/wrapped-token/src/WrappedToken.sol";
import {IERC4626} from "src/Common.sol";
import {Hooks} from "src/Hooks.sol";

contract SetupBase6DecimalsVault is SetupVault {
    MockSwapper public swapper;

    WrappedToken public wusdc;

    function mockUSDCBuffer() public {
        MockERC4626 usdcBuffer = new MockERC4626(ERC20(address(MC.USDC)), "Staked USDC", "sUSDC");
        bytes memory code = address(usdcBuffer).code;
        vm.etch(MC.BUFFER, code);
    }

    function setup() public override returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAx";

        Vault vaultImplementation = new PublicViewsVault();

        // Deploy the proxy
        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, "");

        vault = Vault(payable(address(vaultProxy)));

        // fee module implementation
        Hooks hooks = new Hooks(address(vaultProxy));

        TUProxy hooksProxy = new TUProxy(address(hooks), ADMIN, "");
        hooks = Hooks(payable(address(hooksProxy)));

        // Initialize the vault with the following parameters:
        // ADMIN: The address that will have admin privileges
        // name: The name of the vault token ("YieldNest MAX")
        // symbol: The symbol of the vault token ("ynMAx")
        // 18: The number of decimals for the vault token
        // 0: The withdrawal fee in basis points
        // false: Whether to count native assets (ETH) in the vault
        // false: Whether to always compute total assets (instead of tracking incrementally)
        // 1: The default asset index to use (in this case, the second asset added will be default)
        vault.initialize(ADMIN, name, symbol, 18, 0, false, false, 1);

        weth = WETH9(payable(MC.WETH));

        wusdc = WrappedToken(address(new TUProxy(address(new WrappedToken()), ADMIN, "")));
        wusdc.initialize(IERC20(MC.USDC), "Wrapped USDC", "wUSDC", 18, 12);

        if (block.chainid == 31337) {
            configureLocal(vault, hooks);
        }

        if (block.chainid == 1) {
            configureMainnet(vault);
        }
    }

    function configureLocal(Vault vault, Hooks hooks) internal override {
        mockAll();

        vm.startPrank(ADMIN);

        // Grant roles
        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), HOOKS_MANAGER);

        // Deploy Mock6DecimalsProvider
        Mock6DecimalsProvider mock6DecimalsProvider = new Mock6DecimalsProvider();
        // Set the provider to the 6 decimals provider
        vault.setProvider(address(mock6DecimalsProvider));

        // Add assets: Base asset (USDC) first, then WBTC and an 18 decimal asset

        vault.addAsset(address(wusdc), true);
        vault.addAsset(MC.USDC, true); // USDC mocked at WETH address
        vault.addAsset(MC.BUFFER, false);
        vault.addAsset(MC.WBTC, true);
        vault.addAsset(MC.STETH, true); // 18 decimals asset
        vault.addAsset(MC.USDE, true); // 18 decimals USDE
        vault.addAsset(MC.SUSDE, true); // sUSDE (ERC4626 for USDE)

        // Set rates in provider
        mock6DecimalsProvider.setRate(address(wusdc), 1e18); // 1 USD USDC
        mock6DecimalsProvider.setRate(MC.USDC, 1e18); // 1 USD USDC
        mock6DecimalsProvider.setRate(MC.USDE, 1e18); // 1 USD USDE
        mock6DecimalsProvider.setRate(MC.WBTC, 100_000e18); // 100k USD bitcoin
        mock6DecimalsProvider.setRate(MC.STETH, 10_000e18); // 10k USD steth
        mock6DecimalsProvider.addERC4626(MC.SUSDE);
        mock6DecimalsProvider.addERC4626(MC.BUFFER);

        hooks.initialize(ADMIN, 1e17, FEE_MANAGER);

        vault.unpause();
        vm.stopPrank();

        vm.startPrank(HOOKS_MANAGER);
        vault.setHooks(address(hooks));
        vm.stopPrank();

        {
            // Deposit 100 million USDE to SUSDE vault
            uint256 amount = 100_000_000_000e18;
            address depositor = address(0xDEADBEEF);
            deal(MC.USDE, depositor, amount);
            vm.startPrank(depositor);
            IERC20(MC.USDE).approve(address(MC.SUSDE), amount);
            MockERC4626(MC.SUSDE).deposit(amount, depositor);
            vm.stopPrank();

            // Donate 123456789 USDE to the vault
            address donor = address(0xCAFEBABE);
            uint256 donationAmount = 12_345_678_900e18;
            deal(MC.USDE, donor, donationAmount);
            vm.startPrank(donor);
            IERC20(MC.USDE).approve(address(MC.SUSDE), donationAmount);
            IERC20(MC.USDE).transfer(address(MC.SUSDE), donationAmount);
            vm.stopPrank();
        }

        {
            vm.startPrank(ADMIN);
            // Transfer 10 billion of each asset to the Swapper
            address[] memory swapableAssets = new address[](5);
            swapableAssets[0] = MC.USDC;
            swapableAssets[1] = MC.WBTC;
            swapableAssets[2] = MC.STETH;
            swapableAssets[3] = MC.USDE;
            swapableAssets[4] = MC.SUSDE;
            swapper = setupSwapper(vault, swapableAssets);
            vm.stopPrank();
        }

        {
            vm.startPrank(ADMIN);
            // Configure processor rules
            setDepositRule(vault, MC.BUFFER, address(vault));

            mockUSDCBuffer();

            vault.setBuffer(MC.BUFFER);
            vm.stopPrank();

            // Deposit USDC seed to buffer
            uint256 usdcSeedAmount = 10_000e6; // 1 million USDC (6 decimals)
            address bufferSeeder = address(0xB1111f3);
            deal(MC.USDC, bufferSeeder, usdcSeedAmount);

            vm.startPrank(bufferSeeder);
            IERC20(MC.USDC).approve(MC.BUFFER, usdcSeedAmount);
            IERC4626(MC.BUFFER).deposit(usdcSeedAmount, bufferSeeder);
            vm.stopPrank();

            // Verify the buffer deposit was successful
            require(
                IERC20(MC.BUFFER).balanceOf(bufferSeeder) == usdcSeedAmount, "Vault should have received buffer shares"
            );
        }

        {
            vm.startPrank(ADMIN);
            address[] memory allowList = new address[](3);
            allowList[0] = address(wusdc);
            allowList[1] = address(swapper);
            allowList[2] = address(MC.BUFFER);
            SafeRules.RuleParams memory ruleParams = BaseRules.getApprovalRule(address(MC.USDC), allowList);
            vault.setProcessorRule(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);

            vm.stopPrank();
        }

        {
            vm.startPrank(ADMIN);
            // Configure processor rules for WUSDC

            // Rule for unwrapping WUSDC back to USDC
            SafeRules.RuleParams memory redeemRule = BaseRules.getRedeemRule(address(wusdc), address(vault));
            vault.setProcessorRule(redeemRule.contractAddress, redeemRule.funcSig, redeemRule.rule);

            // Rule for wrapping USDC to WUSDC
            SafeRules.RuleParams memory depositRule = BaseRules.getDepositRule(address(wusdc), address(vault));
            vault.setProcessorRule(depositRule.contractAddress, depositRule.funcSig, depositRule.rule);

            vm.stopPrank();
        }

        {
            // Set up approval rule for USDE to SUSDE
            vm.startPrank(PROCESSOR_MANAGER);
            // Create an allowlist with both SUSDE and swapper
            address[] memory allowList = new address[](2);
            allowList[0] = MC.SUSDE;
            allowList[1] = address(swapper);
            SafeRules.RuleParams memory ruleParams = BaseRules.getApprovalRule(MC.USDE, allowList);
            vault.setProcessorRule(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);
            SafeRules.RuleParams memory depositRuleParams = BaseRules.getDepositRule(MC.SUSDE, address(vault));
            vault.setProcessorRule(depositRuleParams.contractAddress, depositRuleParams.funcSig, depositRuleParams.rule);
            vm.stopPrank();
        }
    }
}

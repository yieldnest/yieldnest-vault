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
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract Setup6DecimalsVault is SetupVault {
    function setup() public override returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAx";

        Vault vaultImplementation = new PublicViewsVault();

        // Deploy the proxy
        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, "");

        vault = Vault(payable(address(vaultProxy)));
        weth = WETH9(payable(MC.WETH));

        // fee module implementation
        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: true,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });
        FeeHooks hooks = new FeeHooks(address(vaultProxy), ADMIN, 1e17, FEE_MANAGER, config);

        // Initialize the vault with the following parameters:
        // ADMIN: The address that will have admin privileges
        // name: The name of the vault token ("YieldNest MAX")
        // symbol: The symbol of the vault token ("ynMAx")
        // 18: The number of decimals for the vault token
        // 0: The withdrawal fee in basis points
        // false: Whether to count native assets (ETH) in the vault
        // false: Whether to always compute total assets (instead of tracking incrementally)
        // 0: The default asset index to use (in this case, the first asset i.e. USDC added will be default)
        vault.initialize(ADMIN, name, symbol, 6, 0, false, false, 0);

        if (block.chainid == 31337) {
            configureLocal(vault, hooks);
        }

        if (block.chainid == 1) {
            configureMainnet(vault);
        }
    }

    function mockUSDCBuffer() public {
        MockERC4626 usdcBuffer = new MockERC4626(ERC20(address(MC.USDC)), "Staked USDC", "sUSDC");
        bytes memory code = address(usdcBuffer).code;
        vm.etch(MC.BUFFER, code);
    }

    function configureLocal(Vault vault, FeeHooks hooks) internal override {
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
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);

        // Deploy Mock6DecimalsProvider
        Mock6DecimalsProvider mock6DecimalsProvider = new Mock6DecimalsProvider();
        // Set the provider to the 6 decimals provider
        vault.setProvider(address(mock6DecimalsProvider));

        mockUSDCBuffer();

        // Add assets: Base asset (USDC) first
        vault.addAsset(MC.USDC, true); // USDC mocked at WETH address
        vault.addAsset(MC.BUFFER, false);
        // Set rates in provider
        mock6DecimalsProvider.setRate(MC.USDC, 1e6); // 1 USD USDC
        mock6DecimalsProvider.addERC4626(MC.BUFFER);

        vault.unpause();
        vm.stopPrank();

        vm.startPrank(HOOKS_MANAGER);
        vault.setHooks(address(hooks));
        vm.stopPrank();

        {
            vm.startPrank(ADMIN);
            // Configure processor rules
            setDepositRule(vault, MC.BUFFER, address(vault));

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
            address[] memory allowList = new address[](1);
            allowList[0] = address(MC.BUFFER);
            SafeRules.RuleParams memory ruleParams = BaseRules.getApprovalRule(address(MC.USDC), allowList);
            vault.setProcessorRule(ruleParams.contractAddress, ruleParams.funcSig, ruleParams.rule);

            vm.stopPrank();
        }
    }
}

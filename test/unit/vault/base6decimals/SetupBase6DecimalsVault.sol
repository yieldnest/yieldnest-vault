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

contract SetupBase6DecimalsVault is SetupVault {
    MockSwapper public swapper;

    function setup() public override returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAx";

        Vault vaultImplementation = new PublicViewsVault();

        // Deploy the proxy
        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, "");

        vault = Vault(payable(address(vaultProxy)));

        // Initialize the vault
        vault.initialize(ADMIN, name, symbol, 18, 0, false, false);

        weth = WETH9(payable(MC.WETH));

        if (block.chainid == 31337) {
            configureLocal(vault);
        }

        if (block.chainid == 1) {
            configureMainnet(vault);
        }
    }

    function configureLocal(Vault vault) internal override {
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
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);

        // Deploy Mock6DecimalsProvider
        Mock6DecimalsProvider mock6DecimalsProvider = new Mock6DecimalsProvider();
        // Set the provider to the 6 decimals provider
        vault.setProvider(address(mock6DecimalsProvider));

        // Add assets: Base asset (USDC) first, then WBTC and an 18 decimal asset
        vault.addAsset(MC.USDC, true); // USDC mocked at WETH address
        vault.addAsset(MC.BUFFER, false);
        vault.addAsset(MC.WBTC, true);
        vault.addAsset(MC.STETH, true); // 18 decimals asset
        vault.addAsset(MC.USDE, true); // 18 decimals USDE
        vault.addAsset(MC.SUSDE, true); // sUSDE (ERC4626 for USDE)

        // Configure processor rules
        setDepositRule(vault, MC.BUFFER, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER);
        setApprovalRule(vault, MC.WETH, MC.BUFFER);

        vault.setBuffer(MC.BUFFER);

        // Set rates in provider
        mock6DecimalsProvider.setRate(MC.USDC, 1e18); // 1 USD USDC
        mock6DecimalsProvider.setRate(MC.USDE, 1e18); // 1 USD USDE
        mock6DecimalsProvider.setRate(MC.WBTC, 100_000e18); // 100k USD bitcoin
        mock6DecimalsProvider.setRate(MC.STETH, 10_000e18); // 10k USD steth
        mock6DecimalsProvider.addERC4626(MC.SUSDE);

        vault.unpause();
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
            swapper = setupSwapper(vault);
            vm.stopPrank();

            // Transfer 10 billion USDC (6 decimals)
            uint256 usdcAmount = 10_000_000_000 * 1e6;
            deal(address(MC.USDC), address(swapper), usdcAmount);

            // Transfer 10 billion WBTC (8 decimals)
            uint256 wbtcAmount = 10_000_000_000 * 1e8;
            deal(address(MC.WBTC), address(swapper), wbtcAmount);

            // Transfer 10 billion STETH (18 decimals)
            uint256 stethAmount = 10_000_000_000 * 1e18;
            deal(address(MC.STETH), address(swapper), stethAmount);

            // Transfer 10 billion USDE (18 decimals)
            uint256 usdeAmount = 10_000_000_000 * 1e18;
            deal(address(MC.USDE), address(swapper), usdeAmount);

            // Transfer 10 billion SUSDE (18 decimals)
            uint256 susdeAmount = 10_000_000_000 * 1e18;
            deal(address(MC.SUSDE), address(swapper), susdeAmount);
        }
    }
}

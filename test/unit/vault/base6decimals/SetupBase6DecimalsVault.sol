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

contract SetupBase6DecimalsVault is SetupVault {
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

        vault.setProvider(MC.PROVIDER);

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
        MockProvider(MC.PROVIDER).setRate(MC.USDC, 1e6); // 1 USD USDC
        MockProvider(MC.PROVIDER).setRate(MC.USDE, 1e6); // 1 USD USDE
        MockProvider(MC.PROVIDER).setRate(MC.WBTC, 100_000e6); // 100k USD bitcoin
        MockProvider(MC.PROVIDER).setRate(MC.STETH, 10_000e6); // 10k USD steth
        MockProvider(MC.PROVIDER).addERC4626(MC.SUSDE);

        vault.unpause();
        vm.stopPrank();

        {
            // Deposit 100 million USDE to SUSDE vault
            uint256 amount = 100_000_000_000e18;
            address depositor = address(0xDEADBEEF);
            deal(MC.USDE, depositor, amount);
            vm.startPrank(depositor);
            IERC20(MC.USDE).approve(address(MC.SUSDE), amount);
            uint256 shares = MockERC4626(MC.SUSDE).deposit(amount, depositor);
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
    }
}

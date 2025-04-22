// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {IVault} from "src/interface/IVault.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {Mock6DecimalsProvider} from "test/unit/mocks/Mock6DecimalsProvider.sol";
import {SetupStrategy} from "test/unit/helpers/SetupStrategy.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";

contract SetupBase6DecimalsBaseStrategy is Test, Etches, MainnetActors, SetupStrategy {
    function setup() public override returns (MockStrategy strategy, WETH9 weth) {
        weth = WETH9(payable(MC.WETH));

        MockProvider provider = new MockProvider();
        provider.setRate(address(weth), 1e18);

        MockStrategy implementation = new MockStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), ADMIN, "");

        strategy = MockStrategy(payable(address(proxy)));
        strategy.initialize("Mock Strategy", "MS", ADMIN, true);

        // Add WETH as an asset to the strategy
        configureLocal(strategy);
    }

    function configureLocal(MockStrategy strategy) internal override {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        strategy.grantRole(strategy.PROCESSOR_ROLE(), PROCESSOR);
        strategy.grantRole(strategy.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        strategy.grantRole(strategy.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        strategy.grantRole(strategy.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        strategy.grantRole(strategy.ALLOCATOR_MANAGER_ROLE(), ALLOCATOR_MANAGER);
        strategy.grantRole(strategy.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        strategy.grantRole(strategy.PAUSER_ROLE(), PAUSER);
        strategy.grantRole(strategy.UNPAUSER_ROLE(), UNPAUSER);

        // set the rate provider contract
        strategy.setProvider(MC.PROVIDER);

        // Add assets: Base asset (USDC) first, then WBTC and an 18 decimal asset
        strategy.addAsset(MC.USDC, true); // USDC mocked at WETH address
        strategy.addAsset(MC.BUFFER, false);
        strategy.addAsset(MC.WBTC, true);
        strategy.addAsset(MC.STETH, true); // 18 decimals asset
        strategy.addAsset(MC.USDE, true); // 18 decimals USDE
        strategy.addAsset(MC.SUSDE, true); // sUSDE (ERC4626 for USDE)

        // Set rates in provider
        Mock6DecimalsProvider mock6DecimalsProvider = new Mock6DecimalsProvider();
        mock6DecimalsProvider.setRate(MC.USDC, 1e18); // 1 USD USDC
        mock6DecimalsProvider.setRate(MC.USDE, 1e18); // 1 USD USDE
        mock6DecimalsProvider.setRate(MC.WBTC, 100_000e18); // 100k USD bitcoin
        mock6DecimalsProvider.setRate(MC.STETH, 10_000e18); // 10k USD steth
        mock6DecimalsProvider.addERC4626(MC.SUSDE);

        strategy.unpause();
        vm.stopPrank();

        {
            // Deposit 100 million USDE to SUSDE strategy
            uint256 amount = 100_000_000_000e18;
            address depositor = address(0xDEADBEEF);
            deal(MC.USDE, depositor, amount);
            vm.startPrank(depositor);
            IERC20(MC.USDE).approve(address(MC.SUSDE), amount);
            uint256 shares = MockERC4626(MC.SUSDE).deposit(amount, depositor);
            vm.stopPrank();

            // Donate 123456789 USDE to the strategy
            address donor = address(0xCAFEBABE);
            uint256 donationAmount = 12_345_678_900e18;
            deal(MC.USDE, donor, donationAmount);
            vm.startPrank(donor);
            IERC20(MC.USDE).approve(address(MC.SUSDE), donationAmount);
            IERC20(MC.USDE).transfer(address(MC.SUSDE), donationAmount);
            vm.stopPrank();
        }

        vm.stopPrank();
    }
}

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
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";

contract SetupStrategy is Test, Etches, MainnetActors {
    function setup() public virtual returns (MockStrategy strategy, WETH9 weth) {
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

    function configureLocal(MockStrategy strategy) internal virtual {
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

        // Add assets: Base asset always first
        strategy.addAsset(MC.WETH, true);
        strategy.addAsset(MC.STETH, true);
        strategy.addAsset(MC.WBTC, true);

        strategy.setAssetWithdrawable(MC.WETH, true);
        strategy.setAssetWithdrawable(MC.STETH, true);
        strategy.setAssetWithdrawable(MC.WBTC, true);

        // Set WBTC rate to 20 ETH
        MockProvider(MC.PROVIDER).setRate(MC.WBTC, 20e18);
        // Set METH rate to 1.2 ETH
        MockProvider(MC.PROVIDER).setRate(MC.METH, 1.2e18);

        vm.stopPrank();
    }
}

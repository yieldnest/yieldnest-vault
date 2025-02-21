// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {TransparentUpgradeableProxy} from "src/Common.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Math} from "src/Common.sol";
import {IERC20, IERC20Metadata} from "src/Common.sol";
import {MockStrategy} from "test/unit/mocks/MockStrategy.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";

contract StrategyViewsUnitTest is Test, Etches {
    using Math for uint256;

    MockStrategy public mockStrategy;
    MockProvider public provider;
    WETH9 public weth;

    address public alice = address(0x1);
    uint256 public constant INITIAL_BALANCE = 100_000 ether;

    function setUp() public {
        weth = WETH9(payable(MC.WETH));
        mockWETH9();
        provider = new MockProvider();
        provider.setRate(address(weth), 1e18);

        MockStrategy implementation = new MockStrategy();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(implementation), address(this), "");

        mockStrategy = MockStrategy(payable(address(proxy)));
        mockStrategy.initialize("Mock Strategy", "MS", address(this), true);

        mockStrategy.grantRole(mockStrategy.ALLOCATOR_MANAGER_ROLE(), address(this));
        mockStrategy.grantRole(mockStrategy.ALLOCATOR_ROLE(), address(this));
        mockStrategy.grantRole(mockStrategy.ASSET_MANAGER_ROLE(), address(this));
        mockStrategy.grantRole(mockStrategy.PROVIDER_MANAGER_ROLE(), address(this));

        mockStrategy.setProvider(address(provider));

        // Add WETH as an asset to the strategy
        mockStrategy.addAsset(
            address(weth), // asset
            18, // decimals
            true, // depositable
            true // withdrawable
        );

        // Give Alice some tokens
        deal(alice, INITIAL_BALANCE);
        weth.deposit{value: INITIAL_BALANCE}();
        weth.transfer(alice, INITIAL_BALANCE);

        // Approve vault to spend Alice's tokens
        vm.prank(alice);
        weth.approve(address(mockStrategy), type(uint256).max);
    }

    function test_Strategy_GetHasAllocator() public {
        mockStrategy.setHasAllocator(true);
        assertEq(mockStrategy.getHasAllocator(), true, "Mock strategy should have allocators");
    }

    function test_Strategy_GetAssetWithdrawable() public {
        mockStrategy.setAssetWithdrawable(MC.WETH, true);
        assertEq(mockStrategy.getAssetWithdrawable(MC.WETH), true, "Mock strategy should have WETH withdrawable");
    }

    function test_Strategy_MaxRedeem() public {
        assertEq(mockStrategy.maxRedeem(address(alice)), 0, "Alice should have max redeem of 0");
        vm.prank(alice);
        mockStrategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            mockStrategy.maxRedeem(address(alice)),
            INITIAL_BALANCE,
            "Alice should have max redeem of INITIAL_BALANCE WETH"
        );
    }

    function test_Strategy_MaxWithdraw() public {
        assertEq(mockStrategy.maxWithdraw(address(alice)), 0, "Alice should have max withdraw of 0");
        vm.prank(alice);
        mockStrategy.deposit(INITIAL_BALANCE, alice);
        assertEq(
            mockStrategy.maxWithdraw(address(alice)),
            INITIAL_BALANCE,
            "Alice should have max withdraw of INITIAL_BALANCE WETH"
        );
    }

    function test_Strategy_PreviewMintAsset() public {
        assertEq(
            mockStrategy.previewMintAsset(address(weth), INITIAL_BALANCE),
            INITIAL_BALANCE,
            "Alice should have preview mint of INITIAL_BALANCE WETH"
        );
    }
}

// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {SetupVault} from "test/mainnet/helpers/SetupVault.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {MainnetActors} from "script/Actors.sol";
import {Vault} from "src/Vault.sol";
import {IERC20, TransparentUpgradeableProxy} from "src/Common.sol";
import {AssertUtils} from "test/utils/AssertUtils.sol";
import {XReferralAdapter} from "src/utils/XReferralAdapter.sol";
import {MockERC4626} from "test/mainnet/mocks/MockERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";


contract VaultMainnetInvariantsTest is Test, AssertUtils, MainnetActors {

    Vault public vault;

    function setUp() public {
        SetupVault setup = new SetupVault();
        setup.upgrade();
        vault = Vault(payable(MC.YNETHX));

        // Deploy mock buffer
        MockERC4626 mockBuffer = new MockERC4626(
            ERC20(MC.WETH),
            "Mock Buffer",
            "BUFF"
        );

        // Set mock buffer address
        vm.prank(ADMIN);
        vault.setBuffer(address(mockBuffer));

        // Grant DEFAULT_ADMIN_ROLE to setup contract
        vm.startPrank(ADMIN);
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), address(setup));
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), address(setup));
        vm.stopPrank();

        setup.setApprovalRule(vault, MC.WETH, address(mockBuffer));
        setup.setDepositRule(vault, address(mockBuffer), address(vault));

        // Remove DEFAULT_ADMIN_ROLE from setup contract
        vm.startPrank(ADMIN);
        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), address(setup));
        vault.revokeRole(vault.PROCESSOR_MANAGER_ROLE(), address(setup));
        vm.stopPrank();

        // Configure mock provider to use ERC4626 rate for buffer
        MockProvider(MC.PROVIDER).addERC4626(address(mockBuffer));
    }

    function totalSupplyInvariant(uint256 supply) public view {
        uint256 finalVaultTotalSupply = vault.totalSupply();
        assertEqThreshold(supply, finalVaultTotalSupply, 3, "Vault totalSupply should be original totalSupply plus additional");
    }

    function totalAssetsInvariant(uint256 assets) public view {
        uint256 finalVaultTotalAssets = vault.totalAssets();
        assertEqThreshold(assets, finalVaultTotalAssets, 3, "Vault totalAssets should be original totalAssets plus additional");
    }    

    function allocateToBuffer(uint256 amount) public {
        address[] memory targets = new address[](2);
        targets[0] = MC.WETH;
        targets[1] = vault.buffer();

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", vault.buffer(), amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, address(vault));

        vm.prank(ADMIN);
        vault.processor(targets, values, data);

        vault.processAccounting();
    }

    function test_Vault_4626Invariants_depositBase_WithBufferAllocation(
        // uint256 assets
    ) public {
        // if (assets < 2) return;
        // if (assets > 100_000_000 ether) return;

        uint256 assets = 100 ether;

        uint256 initialAssets = vault.totalAssets();
        uint256 initialSupply = vault.totalSupply();

        // Test the decimals function
        assertEq(vault.decimals(), 18, "Decimals should be 18");

        // Test the asset function
        assertEq(vault.asset(), MC.WETH, "Asset address should be WETH");

        // Test the totalAssets function
        assertGt(vault.totalAssets(), 0, "Total assets should be greater than 0");

        // Test the convertToShares function
        uint256 shares = vault.convertToShares(assets);
        assertGt(shares, 0, "Shares should be greater than 0");

        assertEqThreshold(vault.convertToAssets(shares), assets, 3, "Converted assets should equal the original assets");

        // Test the previewDeposit function
        deal(address(this), 1 ether);
        (bool success,) = MC.WETH.call{value: 1 ether}("");
        require(success, "Weth deposit failed");
        IERC20(MC.WETH).approve(address(vault), 1 ether);
        IERC20(MC.WETH).transfer(address(vault), 1 ether);

        uint256 previewedShares = vault.previewDeposit(assets);
        assertEqThreshold(previewedShares, shares, 3, "Previewed shares should equal the converted shares");

        // Test the previewMint function
        uint256 previewedAssets = vault.previewMint(shares);
        assertEqThreshold(previewedAssets, assets, 3, "Previewed assets should equal the original assets");

        {
            // Test the depositAsset function
            deal(address(this), assets);
            (success,) = MC.WETH.call{value: assets}("");
            if (!success) revert("Weth deposit failed");
            IERC20(MC.WETH).approve(address(vault), assets);

            address receiver = address(this);
            uint256 depositedShares = vault.deposit(assets, receiver);
            assertEq(depositedShares, shares, "Deposited shares should equal the converted shares");
        }

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);

        uint256 bufferAmount = 10 ether;
        // allocate to buffer
        allocateToBuffer(bufferAmount); 

        totalSupplyInvariant(initialSupply + shares);
        totalAssetsInvariant(initialAssets + assets);
    }
}
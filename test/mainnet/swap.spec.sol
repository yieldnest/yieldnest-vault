// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {BaseTest} from "test/mainnet/helpers/BaseTest.sol";
import {Vault} from "src/Vault.sol";
import {BufferStrategy} from "src/BufferStrategy.sol";
import {Provider} from "src/module/Provider.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IVault} from "src/interface/IVault.sol";

import {console} from "lib/forge-std/src/console.sol";

contract SwapTest is BaseTest {

    using SafeERC20 for IERC20;

    Vault public vault;
    BufferStrategy public bufferStrategy;
    Provider public provider;

    function setUp() public {
        (vault, bufferStrategy, provider) = BaseTest.deploy();
        // Process accounting to ensure vault is in sync
        vault.processAccounting();
    }

    function test_swap_USDC_to_USDT() public {
        uint256 depositAmount = 10000e6;
        
        depositAmount = depositToVault(MC.USDC, depositAmount, 0);
        assertEq(vault.totalAssets(), depositAmount * 1e12);
        
        uint256 usdtBalanceBefore = IERC20(MC.USDT).balanceOf(address(vault));
        uint256 vaultTotalAssetsBefore = vault.totalAssets();
        
        PsPResponse memory response = BaseTest._fetchPSPRoute(MC.USDC, MC.USDT, depositAmount, address(vault));
        processSwap(response, MC.USDC, depositAmount);
        vault.processAccounting();
        
        uint256 usdtBalanceAfter = IERC20(MC.USDT).balanceOf(address(vault));
        uint256 vaultTotalAssetsAfter = vault.totalAssets();

        assertTrue(usdtBalanceAfter > usdtBalanceBefore, "USDT balance should increase after swap");
        uint256 minExpectedTotalAssets = vaultTotalAssetsBefore * (SLIPPAGE_PRECISION - MAX_SLIPPAGE) / SLIPPAGE_PRECISION;
        assertTrue(vaultTotalAssetsAfter >= minExpectedTotalAssets, "Vault total assets should increase after swap");
    }
    
    function test_generic_swap() public {
        address[] memory assets = vault.getAssets();
        giveInfiniteApprovalToAugustusRouter();

        for (uint256 i = 0; i < assets.length; i++) {
            for (uint256 j = i + 1; j < assets.length; j++) {
                address srcToken = assets[i];
                address destToken = assets[j];

                if(srcToken == address(bufferStrategy) || srcToken == address(MC.GHO) || destToken == address(bufferStrategy) || destToken == MC.SUSDS || destToken == MC.SCRVUSD) {
                    continue;
                }

                uint256 depositAmount = 1000 * 10 ** ERC20(srcToken).decimals();
                
                depositAmount = depositToVault(srcToken, depositAmount, i);
                
                uint256 destTokenBalanceBefore = IERC20(destToken).balanceOf(address(vault));
                uint256 vaultTotalAssetsBefore = vault.totalAssets();
                
                PsPResponse memory response = BaseTest._fetchPSPRoute(srcToken, destToken, depositAmount, address(vault));
                processSwap(response, srcToken, depositAmount);
                vault.processAccounting();
                
                uint256 destTokenBalanceAfter = IERC20(destToken).balanceOf(address(vault));
                uint256 vaultTotalAssetsAfter = vault.totalAssets();

                assertTrue(destTokenBalanceAfter > destTokenBalanceBefore, "Dest token balance should increase after swap");
                uint256 minExpectedTotalAssets = vaultTotalAssetsBefore * (SLIPPAGE_PRECISION - MAX_SLIPPAGE) / SLIPPAGE_PRECISION;
                assertTrue(vaultTotalAssetsAfter >= minExpectedTotalAssets, "Vault total assets should be within slippage tolerance");    
            }
        }
    }

    function depositToVault(address asset, uint256 amount, uint256 assetIndex) internal returns (uint256) {
        if (!vault.getAsset(asset).active) {
            vm.startPrank(address(ADMIN));
            IVault.AssetUpdateFields memory fields = IVault.AssetUpdateFields({active: true});
            vault.updateAsset(assetIndex, fields);
            vm.stopPrank();
        }

        address alice = makeAddr("alice");
       uint256 balance = dealAsset(asset, alice, amount);
        vm.startPrank(alice);
        SafeERC20.forceApprove(IERC20(asset), address(vault), balance);
        vault.depositAsset(asset, balance, alice);
        vm.stopPrank();
        return balance;
    }

    function giveInfiniteApprovalToAugustusRouter() internal {
            address[] memory targets = new address[](9);
            uint256[] memory values = new uint256[](9);
            bytes[] memory data = new bytes[](9);

            targets[0] = MC.USDC;
            values[0] = 0;
            data[0] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[1] = MC.USDT;
            values[1] = 0;
            data[1] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[2] = MC.SUSDE;
            values[2] = 0;
            data[2] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[3] = MC.SUSDS;
            values[3] = 0;
            data[3] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[4] = MC.SCRVUSD;
            values[4] = 0;
            data[4] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[5] = MC.USDE;
            values[5] = 0;
            data[5] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[6] = MC.GHO;
            values[6] = 0;
            data[6] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));
            
            targets[7] = MC.SFRAX;
            values[7] = 0;
            data[7] = abi.encodeCall(IERC20.approve, (MC.PARASWAP_AUGUSTUS_SWAPPER_ROUTER, type(uint256).max));

            targets[8] = MC.USDT;
            values[8] = 0;
            data[8] = abi.encodeCall(IERC20.approve, (0x16C6521Dff6baB339122a0FE25a9116693265353, type(uint256).max));

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();
    }

    function processSwap(PsPResponse memory response, address srcToken, uint256 amount) internal {
        {
            address[] memory targets = new address[](1);
            uint256[] memory values = new uint256[](1);
            bytes[] memory data = new bytes[](1);

            targets[0] = address(response.augustus);
            values[0] = 0;
            data[0] = response.swapCalldata;

            vm.startPrank(PROCESSOR);
            bytes[] memory returnData = vault.processor(targets, values, data);
            vm.stopPrank();
        }
    }

}
// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {MainnetContracts as MC} from "script/Contracts.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";

library ProcessorUtils {
    address internal constant CHEATCODE_ADDRESS = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;

    /**
     * @notice Allocates assets to an ERC4626 strategy
     * @param vault The vault address
     * @param asset The asset address to approve
     * @param strategy The ERC4626 strategy address
     * @param amount The amount to allocate
     * @param processor The processor address
     */
    function allocateToERC4626(address vault, address asset, address strategy, uint256 amount, address processor)
        internal
    {
        Vm vm = Vm(CHEATCODE_ADDRESS);
        address[] memory targets = new address[](2);
        targets[0] = asset;
        targets[1] = strategy;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", strategy, amount);
        data[1] = abi.encodeWithSignature("deposit(uint256,address)", amount, vault);

        vm.prank(processor);
        IVault(vault).processor(targets, values, data);
    }

    function allocateToERC4626MAX(address vault, address asset, address strategy, uint256 amount, address processor)
        internal
    {
        Vm vm = Vm(CHEATCODE_ADDRESS);
        address[] memory targets = new address[](2);
        targets[0] = asset;
        targets[1] = strategy;

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSignature("approve(address,uint256)", strategy, amount);
        data[1] = abi.encodeWithSignature("depositAsset(address,uint256,address)", asset, amount, vault);

        vm.prank(processor);
        IVault(vault).processor(targets, values, data);
    }

    /**
     * @notice Withdraws assets from an ERC4626 strategy via the vault processor
     * @param vault The vault address
     * @param strategy The ERC4626 strategy address
     * @param shares The amount of shares to withdraw
     * @param processor The processor address
     */
    function withdrawFromERC4626(address vault, address strategy, uint256 shares, address processor) internal {
        Vm vm = Vm(CHEATCODE_ADDRESS);
        address[] memory targets = new address[](1);
        targets[0] = strategy;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory data = new bytes[](1);
        // Withdraw from the ERC4626 strategy to the vault
        data[0] = abi.encodeWithSignature("withdraw(uint256,address,address)", shares, vault, vault);

        vm.prank(processor);
        IVault(vault).processor(targets, values, data);
    }

    function depositToFxBase(address vault, uint256 depositAmount, address processor) internal {
        Vm vm = Vm(CHEATCODE_ADDRESS);
        // 1. Allocate to fxBASE using processor
        // Prepare calldata for fxBASE.deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        address receiver = address(vault);
        address tokenIn = MC.USDC;
        uint256 amountTokenToDeposit = depositAmount;
        uint256 minSharesOut = 0;

        bytes memory fxBaseDepositCalldata = abi.encodeWithSelector(
            IFxUSDBasePool(MC.FXBASE).deposit.selector, receiver, tokenIn, amountTokenToDeposit, minSharesOut
        );

        // Call processor on the vault to approve fxBASE to spend USDC, then allocate to fxBASE
        // The approve call must come before the fxBASE deposit call
        address[] memory targets1 = new address[](2);
        uint256[] memory values1 = new uint256[](2);
        bytes[] memory calldatas1 = new bytes[](2);

        // 1. Approve fxBASE to spend USDC from the vault
        targets1[0] = MC.USDC;
        values1[0] = 0;
        calldatas1[0] = abi.encodeWithSelector(IERC20(MC.USDC).approve.selector, MC.FXBASE, depositAmount);

        // 2. Call fxBASE.deposit
        targets1[1] = MC.FXBASE;
        values1[1] = 0;
        calldatas1[1] = fxBaseDepositCalldata;

        vm.startPrank(processor);
        IVault(address(vault)).processor(targets1, values1, calldatas1);
        vm.stopPrank();

        IVault(address(vault)).processAccounting();
    }
}

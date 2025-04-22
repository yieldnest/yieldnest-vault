// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {BaseStrategy} from "src/strategy/BaseStrategy.sol";
import {MainnetContracts} from "script/Contracts.sol";
import {IERC20} from "src/Common.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20Metadata} from "src/Common.sol";
import {IVault} from "src/interface/IVault.sol";
import {IERC20Metadata, Math} from "src/Common.sol";

contract MockSwapper {
    using Math for uint256;

    /**
     * @dev Calculates floor(a×b÷c) with full precision. Throws if result overflows a uint256 or when c is zero.
     *
     * @param a The multiplicand
     * @param b The multiplier
     * @param c The divisor
     * @param rounding The rounding direction
     * @return result The result of floor(a×b÷c)
     */
    function mulDiv(uint256 a, uint256 b, uint256 c, Math.Rounding rounding) internal pure returns (uint256 result) {
        return Math.mulDiv(a, b, c, rounding);
    }

    IProvider public provider;

    /**
     * @notice Constructor that sets the provider address
     * @param _provider The address of the provider to use for swaps
     */
    constructor(address _provider) {
        provider = IProvider(_provider);
    }

    function convertAssetToBase(address asset_, uint256 assets) public view returns (uint256 baseAssets) {
        if (asset_ == address(0)) revert IVault.ZeroAddress();

        uint256 rate = provider.getRate(asset_);
        baseAssets = assets.mulDiv(rate, 10 ** IERC20Metadata(asset_).decimals(), Math.Rounding.Floor);
    }

    function convertBaseToAsset(address asset_, uint256 baseAssets) public view returns (uint256 assets) {
        if (asset_ == address(0)) revert IVault.ZeroAddress();

        uint256 rate = provider.getRate(asset_);
        assets = baseAssets.mulDiv(10 ** IERC20Metadata(asset_).decimals(), rate, Math.Rounding.Floor);
    }


    /**
     * @notice Previews the amount of tokenOut that would be received for a given amount of tokenIn
     * @param tokenIn The address of the input token
     * @param tokenOut The address of the output token
     * @param amountIn The amount of input token
     * @return amountOut The amount of output token that would be received
     */
    function previewSwap(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256 amountOut) {
        // Convert tokenIn to base assets
        uint256 baseAssets = convertAssetToBase(tokenIn, amountIn);

        // Convert base assets to tokenOut
        amountOut = convertBaseToAsset(tokenOut, baseAssets);

        return amountOut;
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        // Transfer tokenIn from sender to this contract
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // Use previewSwap to calculate the amount out
        amountOut = previewSwap(tokenIn, tokenOut, amountIn);

        // Transfer the calculated amount of tokenOut to the sender
        IERC20(tokenOut).transfer(msg.sender, amountOut);

        return amountOut;
    }
}

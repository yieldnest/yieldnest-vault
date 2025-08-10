// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "src/Common.sol";

/// @title IFxUSDBasePool
/// @notice Interface for the FxUSD Base Pool contract.
interface IFxUSDBasePool is IERC20 {
    struct RedeemRequest {
        uint128 amount;
        uint128 unlockAt;
    }

    function redeemRequests(address owner) external view returns (RedeemRequest memory);

    /// @notice Returns the total amount of yield token in the pool.
    function totalYieldToken() external view returns (uint256);

    /// @notice Returns the total amount of stable token in the pool.
    function totalStableToken() external view returns (uint256);

    /// @notice Returns the address of the yield token (fxUSD).
    function yieldToken() external view returns (address);

    /// @notice Returns the address of the stable token (USDC).
    function stableToken() external view returns (address);

    /// @notice Returns the NAV (Net Asset Value) of the pool.
    function nav() external view returns (uint256);

    /// @notice Returns the preview of shares to be minted for a deposit.
    /// @param tokenIn The address of the token to deposit.
    /// @param amountTokenToDeposit The amount of token to deposit.
    /// @return amountSharesOut The amount of shares that would be minted.
    function previewDeposit(address tokenIn, uint256 amountTokenToDeposit)
        external
        view
        returns (uint256 amountSharesOut);

    /// @notice Returns the preview of tokens to be received for a redeem.
    /// @param amountSharesToRedeem The amount of shares to redeem.
    /// @return amountYieldOut The amount of yield token to receive.
    /// @return amountStableOut The amount of stable token to receive.
    function previewRedeem(uint256 amountSharesToRedeem)
        external
        view
        returns (uint256 amountYieldOut, uint256 amountStableOut);

    /// @notice Returns the price of the stable token (USDC) from Chainlink.
    function getStableTokenPrice() external view returns (uint256);

    /// @notice Returns the price of the stable token (USDC) with scale.
    function getStableTokenPriceWithScale() external view returns (uint256);

    /// @notice Deposit tokens into the pool.
    /// @param receiver The address to receive the minted shares.
    /// @param tokenIn The address of the token to deposit.
    /// @param amountTokenToDeposit The amount of token to deposit.
    /// @param minSharesOut The minimum amount of shares to mint.
    /// @return amountSharesOut The amount of shares minted.
    function deposit(address receiver, address tokenIn, uint256 amountTokenToDeposit, uint256 minSharesOut)
        external
        returns (uint256 amountSharesOut);

    /// @notice Request to redeem shares (starts the cool down period).
    /// @param shares The amount of shares to redeem.
    function requestRedeem(uint256 shares) external;

    /// @notice Redeem shares for yield and stable tokens after cool down.
    /// @param receiver The address to receive the tokens.
    /// @param amountSharesToRedeem The amount of shares to redeem.
    /// @return amountYieldOut The amount of yield token received.
    /// @return amountStableOut The amount of stable token received.
    function redeem(address receiver, uint256 amountSharesToRedeem)
        external
        returns (uint256 amountYieldOut, uint256 amountStableOut);

    /// @notice Rebalance the pool using tickId.
    /// @param pool The address of the pool.
    /// @param tickId The tick id for rebalance.
    /// @param tokenIn The address of the input token.
    /// @param maxAmount The maximum amount of input token.
    /// @param minCollOut The minimum collateral out.
    /// @return tokenUsed The amount of input token used.
    /// @return colls The amount of collateral received.
    function rebalance(address pool, int16 tickId, address tokenIn, uint256 maxAmount, uint256 minCollOut)
        external
        returns (uint256 tokenUsed, uint256 colls);

    /// @notice Rebalance the pool using positionId.
    /// @param pool The address of the pool.
    /// @param positionId The position id for rebalance.
    /// @param tokenIn The address of the input token.
    /// @param maxAmount The maximum amount of input token.
    /// @param minCollOut The minimum collateral out.
    /// @return tokenUsed The amount of input token used.
    /// @return colls The amount of collateral received.
    function rebalance(address pool, uint32 positionId, address tokenIn, uint256 maxAmount, uint256 minCollOut)
        external
        returns (uint256 tokenUsed, uint256 colls);

    /// @notice Liquidate a position in the pool.
    /// @param pool The address of the pool.
    /// @param positionId The position id to liquidate.
    /// @param tokenIn The address of the input token.
    /// @param maxAmount The maximum amount of input token.
    /// @param minCollOut The minimum collateral out.
    /// @return tokenUsed The amount of input token used.
    /// @return colls The amount of collateral received.
    function liquidate(address pool, uint32 positionId, address tokenIn, uint256 maxAmount, uint256 minCollOut)
        external
        returns (uint256 tokenUsed, uint256 colls);

    /// @notice Perform arbitrage between yield and stable tokens.
    /// @param srcToken The address of the source token.
    /// @param amountIn The amount of source token.
    /// @param receiver The address to receive the bonus.
    /// @param data Arbitrage data.
    /// @return amountOut The amount of destination token out.
    /// @return bonusOut The bonus amount out.
    function arbitrage(address srcToken, uint256 amountIn, address receiver, bytes calldata data)
        external
        returns (uint256 amountOut, uint256 bonusOut);

    /// @notice Update the stable depeg price.
    /// @param newPrice The new depeg price (1e18 precision).
    function updateStableDepegPrice(uint256 newPrice) external;

    /// @notice Update the redeem cool down period.
    /// @param newPeriod The new cool down period in seconds.
    function updateRedeemCoolDownPeriod(uint256 newPeriod) external;
}

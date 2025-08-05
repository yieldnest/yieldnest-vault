// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFxUSDBasePoolFacet {
    /// @notice The struct for input token convert parameters.
    ///
    /// @param tokenIn The address of source token.
    /// @param amount The amount of source token.
    /// @param target The address of converter contract.
    /// @param data The calldata passing to the target contract.
    /// @param minOut The minimum amount of output token should receive.
    /// @param signature The optional data for future usage.
    struct ConvertInParams {
        address tokenIn;
        uint256 amount;
        address target;
        bytes data;
        uint256 minOut;
        bytes signature;
    }

    /// @notice The struct for output token convert parameters.
    /// @param tokenOut The address of output token.
    /// @param converter The address of converter contract.
    /// @param encodings The encodings for `MultiPathConverter`.
    /// @param minOut The minimum amount of output token should receive.
    /// @param routes The convert route encodings.
    /// @param signature The optional data for future usage.
    struct ConvertOutParams {
        address tokenOut;
        address converter;
        uint256 encodings;
        uint256[] routes;
        uint256 minOut;
        bytes signature;
    }

    /// @notice Migrate fxUSD from rebalance pool to fxBASE.
    /// @param pool The address of rebalance pool.
    /// @param amountIn The amount of rebalance pool shares to migrate.
    /// @param minShares The minimum shares should receive.
    /// @param receiver The address of fxBASE share recipient.
    function migrateToFxBase(address pool, uint256 amountIn, uint256 minShares, address receiver) external;

    /// @notice Migrate fxUSD from rebalance pool to fxBASE gauge.
    /// @param pool The address of rebalance pool.
    /// @param amountIn The amount of rebalance pool shares to migrate.
    /// @param minShares The minimum shares should receive.
    /// @param receiver The address of fxBASE share recipient.
    function migrateToFxBaseGauge(address pool, uint256 amountIn, uint256 minShares, address receiver) external;

    /// @notice Deposit token to fxBASE.
    /// @param params The parameters to convert source token to `tokenOut`.
    /// @param tokenOut The target token, USDC or fxUSD.
    /// @param minShares The minimum shares should receive.
    /// @param receiver The address of fxBASE share recipient.
    function depositToFxBase(ConvertInParams memory params, address tokenOut, uint256 minShares, address receiver)
        external
        payable;

    /// @notice Deposit token to fxBase and then deposit to gauge.
    /// @param params The parameters to convert source token to `tokenOut`.
    /// @param tokenOut The target token, USDC or fxUSD.
    /// @param minShares The minimum shares should receive.
    /// @param receiver The address of gauge share recipient.
    function depositToFxBaseGauge(ConvertInParams memory params, address tokenOut, uint256 minShares, address receiver)
        external
        payable;
}

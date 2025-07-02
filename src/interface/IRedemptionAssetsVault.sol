// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRedemptionAssetsVault {
    // Events
    event AssetsDeposited(address indexed asset, address indexed depositor, uint256 amount);
    event AssetTransferred(address indexed asset, address indexed redeemer, address indexed to, uint256 amount);
    event AssetWithdrawn(address indexed asset, address indexed redeemer, address indexed to, uint256 amount);
    event TotalAssetsTransferred(address indexed asset, address indexed from, address indexed to, uint256 amount);

    /// @notice Transfers redemption assets to a specified address based on redemption.
    /// @dev This is only for INTERNAL USE
    /// @param to The address to which the assets will be transferred.
    /// @param amount The amount in unit of account
    /// @param data Extra data payload for redemption request
    function transferRedemptionAssets(address to, uint256 amount, bytes calldata data) external;

    /// @notice Withdraws redemption assets from the queue's balance
    /// @param amount The amount in unit of account
    function withdrawRedemptionAssets(uint256 amount) external;

    /// @notice Retrieves the current redemption rate for the asset in the unit of account.
    /// @return The current redemption rate
    function redemptionRate() external view returns (uint256);

    /// @notice Gets the total amount of redemption assets available for withdrawal in the unit of account.
    /// @return The available amount of redemption assets
    function availableRedemptionAssets() external view returns (uint256);
}

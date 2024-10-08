// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRateProvider {
    /**
     * @dev Returns the current rate for the given asset.
     * @param asset The address of the asset to get the rate for.
     * @return The current rate for the asset.
     */
    function rate(address asset) external view returns (uint256);

    /**
     * @dev Converts the given amount of an asset to its value based on the current rate.
     * @param asset The address of the asset to convert.
     * @param amount The amount of the asset to convert.
     * @return The converted value of the asset amount.
     */
    function convert(address asset, uint256 amount) external view returns (uint256);
}


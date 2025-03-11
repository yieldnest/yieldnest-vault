// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IProvider {
    function getRate(address asset) external view returns (uint256);
    /**
     * @notice Returns the rate offset used for rate calculations
     * @dev This function provides the decimal offset used when calculating exchange rates
     * between different assets. Similar to ERC4626's _decimalsOffset(), it helps standardize
     * rates across assets with different decimal places to 18 decimals.
     * @return The rate offset value as a uint256
     */
    function rateOffset() external view returns (uint256);

    /**
     * @notice Returns both the rate and rate offset for an asset in a single call
     * @param asset The address of the asset to get the rate for
     * @return rate The current exchange rate of the asset
     * @return offset The rate offset used for calculations
     */
    function getRateAndOffset(address asset) external view returns (uint256 rate, uint256 offset);
}

interface IStETH {
    function getPooledEthByShares(uint256 _ethAmount) external view returns (uint256);
}

interface IMETH {
    function mETHToETH(uint256 mETHAmount) external view returns (uint256);
}

interface IOETH {
    function assetToEth(uint256 _assetAmount) external view returns (uint256);
}

interface IRETH {
    function getExchangeRate() external view returns (uint256);
}

interface IswETH {
    function swETHToETHRate() external view returns (uint256);
}

interface IsfrxETH {
    function pricePerShare() external view returns (uint256);
}

interface IFrxEthWethDualOracle {
    function getCurveEmaEthPerFrxEth() external view returns (uint256);
}

interface IynLSDe {
    function convertToAssets(address asset, uint256 shares) external view returns (uint256);
    function previewRedeem(uint256 shares) external view returns (uint256);
}

interface ICurveLpConnector {
    function rate() external view returns (int256 rate, uint256 updatedAt);
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IProvider {
    function getRate(address asset) external view returns (uint256);
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

interface IChainlinkAggregator {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

interface IAaveV3Pool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256);
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    function setUserEMode(uint8 categoryId) external;
}

interface IAaveV3Oracle {
    function getAssetPrice(address asset) external view returns (uint256);
    function BASE_CURRENCY_UNIT() external view returns (uint256);
}

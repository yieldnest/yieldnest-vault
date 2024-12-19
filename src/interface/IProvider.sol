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

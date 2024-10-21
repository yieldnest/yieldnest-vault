// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IRateProvider} from "src/interface/IRateProvider.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

interface IStETH {
    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256);
}

interface IMETH {
    function ratio() external view returns (uint256);
}

interface IOETH {
    function assetToEth(uint256 _assetAmount) external view returns (uint256);
}

interface IRETH {
    function getExchangeRate() external view returns (uint256);
}

interface AggregatorV3Interface {
  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}


contract ETHRateProvider is IRateProvider, Ownable {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1&search=stETH
    address public constant CL_STETH_FEED = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;
    
    mapping(address => uint256) private _manualRates;

    error UnsupportedAsset(address asset);

    constructor() Ownable(msg.sender) {}

    function getRate(address asset) external view override returns (uint256) {
        if (asset == WETH) {
            return 1e18; // WETH is 1:1 with ETH
        } else if (asset == STETH) {
            return _getStETHRate();
        } else if (asset == METH) {
            return _getMETHRate();
        } else if (asset == OETH) {
            return _getOETHRate();
        } else if (asset == RETH) {
            return _getRETHRate();
        } else if (_manualRates[asset] != 0) {
            return _manualRates[asset];
        }
        revert UnsupportedAsset(asset);
    }

    function _getStETHRate() internal view returns (uint256) {
        (,int256 stETHChainlinkRate,,,) = AggregatorV3Interface(CL_STETH_FEED).latestRoundData();
        uint256 stETHContractRate = IStETH(STETH).getSharesByPooledEth(1e18);
        
        // Implementing a weighted average based on the reliability or volume of each source
        // Assuming Chainlink feed is more reliable and has a higher volume, we give it a weight of 0.7
        // The stETH rate from the contract has a weight of 0.3
        uint256 weightedStETHRateChainlink = (uint256(stETHChainlinkRate) * 7) / 10;
        uint256 weightedStETHRateContract = (stETHContractRate * 3) / 10;
        
        // Calculate the final rate as a weighted average of the two sources
        return weightedStETHRateChainlink + weightedStETHRateContract;
    }

    function _getMETHRate() internal view returns (uint256) {
        return IMETH(METH).ratio();
    }

    function _getOETHRate() internal view returns (uint256) {
        return IOETH(OETH).assetToEth(1e18);
    }

    function _getRETHRate() internal view returns (uint256) {
        return IRETH(RETH).getExchangeRate();
    }

    function setManualRate(address asset, uint256 rate) external onlyOwner {
        _manualRates[asset] = rate;
    }
}

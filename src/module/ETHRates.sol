// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IRateProvider} from "src/interface/IRateProvider.sol";
import {IERC4626} from "src/Common.sol";

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

contract ETHRates is IRateProvider {
    // assets
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant METH = 0xd5F7838F5C461fefF7FE49ea5ebaF7728bB0ADfa;
    address public constant OETH = 0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3;
    address public constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

    // strategies
    address public constant YNETH = 0x09db87A538BD693E9d08544577d5cCfAA6373A48;
    address public constant YNLSDE = 0x35Ec69A77B79c255e5d47D5A3BdbEFEfE342630c;
    address public constant BUFFER = 0x000000000000000000000000000000003ADe68b1; // TODO: update this

    error UnsupportedAsset(address asset);

    function getRate(address asset) external view override returns (uint256) {
        if (asset == WETH) {
            return 1e18;
        } else if (asset == STETH) {
            return _getStETHRate();
        } else if (asset == METH) {
            return _getMETHRate();
        } else if (asset == OETH) {
            return _getOETHRate();
        } else if (asset == RETH) {
            return _getRETHRate();
        } else if (asset == YNETH) {
            return _getYNETHRate();
        } else if (asset == YNLSDE) {
            return _getYNLSDERate();
        } else if (asset == BUFFER) {
            return _getBUFFERRate();
        }

        revert UnsupportedAsset(asset);
    }

    function _getStETHRate() internal view returns (uint256) {
        return IStETH(STETH).getSharesByPooledEth(1e18);
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

    function _getYNETHRate() internal view returns (uint256) {
        return IERC4626(YNETH).previewRedeem(1e18);
    }

    function _getYNLSDERate() internal view returns (uint256) {
        IERC4626 ynlsde = IERC4626(YNLSDE);
        uint256 totalAssets = ynlsde.totalAssets();
        uint256 totalSupply = ynlsde.totalSupply();
        if (totalSupply == 0 || totalAssets == 0) return 1e18;
        return (totalAssets * 1e18) / totalSupply;
    }

    function _getBUFFERRate() internal view returns (uint256) {
        return IERC4626(BUFFER).convertToShares(1e18);
    }
}

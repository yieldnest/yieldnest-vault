// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

/*
    The Provider fetches state from other contracts.
*/

contract Provider is IProvider {
    error UnsupportedAsset(address asset);

    mapping(address => uint256) public rates; // in WETH

    function getRate(address asset) external view override returns (uint256) {
        if (asset == MC.WETH) {
            return 1e18;
        } else if (asset == MC.YNETH) {
            return rates[asset]; //IERC4626(MC.YNETH).previewRedeem(1e18);
        } else if (asset == MC.YNLSDE) {
            return IERC4626(MC.YNLSDE).previewRedeem(1e18);
        } else if (asset == MC.BUFFER) {
            return IERC4626(MC.BUFFER).previewRedeem(1e18);
        } else if (asset == MC.STETH) {
            return 1e18;
        } else if (asset == MC.WSTETH) {
            return IStETH(MC.STETH).getPooledEthByShares(1e18);
        } else if (asset == MC.METH) {
            return IMETH(MC.METH).ratio();
        } else if (asset == MC.OETH) {
            return IOETH(MC.OETH).assetToEth(1e18);
        } else if (asset == MC.RETH) {
            return IRETH(MC.RETH).getExchangeRate();
        }

        revert UnsupportedAsset(asset);
    }

    function otherAssets(address vault, address strategy) public view returns (uint256 assets) {
        if (strategy == MC.YNETH) {
            (uint256[] memory withdrawalIndexes, WithdrawalRequest[] memory requests) =
                IynETHwm(MC.YNETH_WM).withdrawalRequestsForOwner(vault);

            uint256 length = withdrawalIndexes.length;
            if (length == 0) return 0;

            uint256 ynethRate = IERC4626(MC.YNETH).previewRedeem(1e18);
            for (uint256 i = 0; i < length; i++) {
                if (!requests[i].processed) {
                    assets += requests[i].amount * ynethRate / 1e18;
                }
            }
        } else if (strategy == MC.YNLSDE) {
            // TODO
            assets = 0;
        }

        // if strategy not handled, return 0 for other assets.
        assets = 0;
    }
}

interface IStETH {
    function getPooledEthByShares(uint256 _ethAmount) external view returns (uint256);
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

struct WithdrawalRequest {
    uint256 amount;
    uint256 feeAtRequestTime;
    uint256 redemptionRateAtRequestTime;
    uint256 creationTimestamp;
    bool processed;
    bytes data;
}

interface IynETHwm {
    function withdrawalRequestsForOwner(address owner)
        external
        view
        returns (uint256[] memory withdrawalIndexes, WithdrawalRequest[] memory requests);
}

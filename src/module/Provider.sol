// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IProvider} from "src/interface/IProvider.sol";
import {IERC4626} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IVault} from "src/interface/IVault.sol";
import {IFxUSDBasePool} from "src/interface/IFxUSDBasePool.sol";
import {Math} from "src/Common.sol";

interface IBaseStrategy {
    function STRATEGY_VERSION() external view returns (string memory);
}

/**
 * @title Provider
 * @notice The Provider is a contract that provides a rate for a given asset in terms of base asset of the vault.
 * @dev The base asset for ynUSDx is Wrapped USDC with 18 decimals.
 * @dev This contract returns the rate of 1 unit of asset(with X decimals) denominated in 1 unit of base asset(with 18 decimals).
 */
contract Provider is IProvider {
    error UnsupportedAsset(address asset);
    error RateIsNegative();

    using Math for uint256;

    address public wrappedUSDC;

    /**
     * @notice Constructor
     * @param wrappedUSDC_ The address of the wrapped USDC asset
     */
    constructor(address wrappedUSDC_) {
        wrappedUSDC = wrappedUSDC_;
    }

    function isUSDCStrategyVault(address asset) public view returns (bool) {
        try IBaseStrategy(asset).STRATEGY_VERSION() returns (string memory version) {
            address vaultAsset = IVault(asset).asset();
            return (keccak256(bytes(version)) == keccak256(bytes("0.2.0"))) && vaultAsset == MC.USDC;
        } catch {
            return false;
        }
    }

    /**
     * @notice Get the rate of a given asset in terms of base asset
     * @param asset The address of the asset
     * @return rate The rate of 1 unit of asset in terms of 1 unit of base asset
     */
    function getRate(address asset) public view virtual returns (uint256) {
        if (asset == wrappedUSDC) {
            return 1e18;
        }

        // 1 USDC = 1 Wrapped USDC
        // 1 unit of USDC with 6 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.USDC) {
            return 1e18;
        }

        // 1 USDT = 1 Wrapped USDC
        // 1 unit of USDT with 6 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.USDT) {
            return 1e18;
        }

        // 1 GHO = 1 Wrapped USDC
        // 1 unit of GHO with 18 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.GHO) {
            return 1e18;
        }

        // 1 USDE = 1 Wrapped USDC
        // 1 unit of USDE with 18 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.USDE) {
            return 1e18;
        }

        // 1 CRVUSD = 1 Wrapped USDC
        // 1 unit of CRVUSD with 18 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.CRVUSD) {
            return 1e18;
        }

        // 1 USDS = 1 Wrapped USDC
        // 1 unit of USDS with 6 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.USDS) {
            return 1e18;
        }

        // 1 FRAX = 1 Wrapped USDC
        // 1 unit of FRAX with 18 decimals is equal to 1 unit of Wrapped USDC with 18 decimals
        if (asset == MC.FRAX) {
            return 1e18;
        }

        if (asset == MC.FXUSD) {
            return 1e18;
        }

        if (asset == MC.FXBASE) {
            // For FXBASE, previewRedeem(1e18) returns how much fxUSD (18 decimals) and USDC (6 decimals) you get for 1 share.
            // We convert both to Wrapped USDC value and sum them.
            (uint256 amountYieldOut, uint256 amountStableOut) = IFxUSDBasePool(MC.FXBASE).previewRedeem(1e18);
            return amountYieldOut * getRate(MC.FXUSD) / 1e18 + amountStableOut * getRate(MC.USDC) / 1e6;
        }

        if (asset == MC.FXSAVE) {
            return IERC4626(MC.FXSAVE).convertToAssets(1e18).mulDiv(getRate(MC.FXBASE), 1e18);
        }

        // base asset of SFRAX, SUSDE, SUSDS, SCRVUSD is FRAX, USDE, USDS, CRVUSD respectively with 18 decimals.
        // we need rate in terms of 18 decimals(denominated in Wrapped USDC) so we query it for 1e18 Wrapped USDC
        if (asset == MC.SFRAX || asset == MC.SUSDE || asset == MC.SUSDS || asset == MC.SCRVUSD) {
            return IERC4626(asset).convertToAssets(1e18);
        }

        if (asset == MC.SUPER_USDC_VAULT) {
            // baseAsset of superUSDC vault is USDC with 6 decimals.
            // we need rate in terms of 18 decimals so we query it for 1e18 Wrapped USDC
            return IERC4626(asset).convertToAssets(1e18);
        }

        // buffer strategy
        if (asset == MC.MORPHO_GAUNTLET_USDC_VAULT) {
            // base asset is USDC with 6 decimals. we scale it to 18 decimals
            return IERC4626(asset).convertToAssets(1e18) * 1e12;
        }

        if (isUSDCStrategyVault(asset)) {
            // base asset is USDC with 6 decimals. we scale it to 18 decimals to convert to Wrapped USDC
            return IERC4626(asset).convertToAssets(1e18) * 1e12;
        }

        revert UnsupportedAsset(asset);
    }
}

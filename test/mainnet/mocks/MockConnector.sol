// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {ICurveLpConnector} from "src/interface/ICurveLpConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurvePool} from "src/interface/external/curve/ICurvePool.sol";
import {IStrategy} from "src/interface/IStrategy.sol";

/// @title ynMaxVault <--> Curve LP <--> ERC4626 Strategy Connector
/// @dev This contract is only suitable for Curve pools with 2 assets
/// @notice Connects the ynMaxVault with a ERC4626 Strategy that accepts Curve LP tokens
contract MockConnector is ICurveLpConnector {
    using SafeERC20 for IERC20;

    error InvalidSender();
    error ZeroAmount();
    error ZeroAddress();

    uint256 public immutable INDEX_ASSET_A;
    uint256 public immutable INDEX_ASSET_B;

    address public immutable VAULT;

    ICurvePool public immutable CURVE_POOL;
    IStrategy public immutable STRATEGY;

    IERC20 public immutable ASSET_A;
    IERC20 public immutable ASSET_B;

    int256 public storedRate;
    uint256 public timestamp;

    constructor(address _vault, address _strategy, address _assetA, address _assetB) {
        VAULT = _vault;
        STRATEGY = IStrategy(_strategy);
        ASSET_A = IERC20(_assetA);
        ASSET_B = IERC20(_assetB);
        CURVE_POOL = ICurvePool(STRATEGY.asset());

        if (CURVE_POOL.coins(0) == _assetA) {
            INDEX_ASSET_A = 0;
            INDEX_ASSET_B = 1;
        } else {
            INDEX_ASSET_A = 1;
            INDEX_ASSET_B = 0;
        }
    }

    function initialize(uint256 _timestamp, int256 _rate) external {
        ASSET_A.forceApprove(address(CURVE_POOL), type(uint256).max);
        ASSET_B.forceApprove(address(CURVE_POOL), type(uint256).max);
        IERC20(address(CURVE_POOL)).forceApprove(address(STRATEGY), type(uint256).max);
        timestamp = _timestamp;
        storedRate = _rate;
    }

    function rate() external view returns (int256, uint256) {
        return (storedRate, timestamp);
    }

    function setTimeStamp(uint256 _timestamp) external {
        timestamp = _timestamp;
    }

    function setRate(int256 _rate) external {
        storedRate = _rate;
    }

    function deposit(uint256 _amountA, uint256 _amountB, uint256 _minOut) external returns (uint256) {
        if (msg.sender != VAULT) revert InvalidSender();
        if (_amountA == 0 && _amountB == 0) revert ZeroAmount();

        if (_amountA > 0) ASSET_A.safeTransferFrom(msg.sender, address(this), _amountA);
        if (_amountB > 0) ASSET_B.safeTransferFrom(msg.sender, address(this), _amountB);

        uint256[] memory _amounts = new uint256[](2);
        _amounts[INDEX_ASSET_A] = _amountA;
        _amounts[INDEX_ASSET_B] = _amountB;
        CURVE_POOL.add_liquidity(_amounts, _minOut);

        uint256 _balance = CURVE_POOL.balanceOf(address(this));
        if (_balance == 0) revert ZeroAmount();

        return STRATEGY.deposit(_balance, msg.sender);
    }

    function withdraw(uint256 _amount, uint256 _minAmountA, uint256 _minAmountB) external returns (uint256[2] memory) {
        if (msg.sender != VAULT) revert InvalidSender();
        if (_amount == 0) revert ZeroAmount();

        STRATEGY.redeem(_amount, address(this), VAULT);

        uint256 _balance = CURVE_POOL.balanceOf(address(this));
        if (_balance == 0) revert ZeroAmount();

        uint256[] memory _minAmounts = new uint256[](2);
        _minAmounts[INDEX_ASSET_A] = _minAmountA;
        _minAmounts[INDEX_ASSET_B] = _minAmountB;

        return CURVE_POOL.remove_liquidity(_balance, _minAmounts, msg.sender);
    }
}

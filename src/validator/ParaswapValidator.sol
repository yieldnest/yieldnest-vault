// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IValidator} from "src/interface/IValidator.sol";
import {IAugustusV6} from "src/interface/IAugustusV6.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

error InvalidValue();
error InvalidTarget();
error InvalidYnUSDx();
error InvalidBeneficiary();
error SlippageTooHigh();
error InvalidSelector();
error InvalidToken();

contract ParaswapValidator is IValidator {
    address public immutable PARASWAP_AUGUSTUS;
    address public immutable YnUSDx;
    address public immutable provider;
    uint256 public immutable maxSlippage;
    uint256 public constant SLIPPAGE_PRECISION = 10000; // 100%
    mapping(address => bool) public supportedTokens;

    constructor(
        address _paraswapAugustus,
        address _ynUSDx,
        address _provider,
        uint256 _maxSlippage,
        address[] memory _supportedTokens
    ) {
        PARASWAP_AUGUSTUS = _paraswapAugustus;
        YnUSDx = _ynUSDx;
        provider = _provider;
        maxSlippage = _maxSlippage;
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
        }
    }

    function validate(address target, uint256 value, bytes calldata data) external view {
        if (value > 0) {
            revert InvalidValue();
        }

        if (target != PARASWAP_AUGUSTUS) {
            revert InvalidTarget();
        }

        if (YnUSDx == address(0)) {
            revert InvalidYnUSDx();
        }

        bytes4 selector = bytes4(data[:4]);
        address beneficiary;
        IERC20 srcToken;
        IERC20 destToken;
        uint256 srcAmount;
        uint256 quotedAmount;

        if (selector == IAugustusV6.swapExactAmountIn.selector) {
            (, IAugustusV6.GenericData memory swapData,,,) =
                abi.decode(data[4:], (address, IAugustusV6.GenericData, uint256, bytes, bytes));
            beneficiary = swapData.beneficiary;
            srcToken = swapData.srcToken;
            destToken = swapData.destToken;
            srcAmount = swapData.fromAmount;
            quotedAmount = swapData.quotedAmount;
        } else if (selector == IAugustusV6.swapExactAmountInOnCurveV1.selector) {
            (IAugustusV6.CurveV1Data memory curveV1Data,,) =
                abi.decode(data[4:], (IAugustusV6.CurveV1Data, uint256, bytes));
            beneficiary = curveV1Data.beneficiary;
            srcToken = curveV1Data.srcToken;
            destToken = curveV1Data.destToken;
            srcAmount = curveV1Data.fromAmount;
            quotedAmount = curveV1Data.quotedAmount;
        } else if (selector == IAugustusV6.swapExactAmountInOnCurveV2.selector) {
            (IAugustusV6.CurveV2Data memory curveV2Data,,) =
                abi.decode(data[4:], (IAugustusV6.CurveV2Data, uint256, bytes));
            beneficiary = curveV2Data.beneficiary;
            srcToken = curveV2Data.srcToken;
            destToken = curveV2Data.destToken;
            srcAmount = curveV2Data.fromAmount;
            quotedAmount = curveV2Data.quotedAmount;
        } else if (selector == IAugustusV6.swapExactAmountInOnUniswapV2.selector) {
            (IAugustusV6.UniswapV2Data memory uniswapV2Data,,) =
                abi.decode(data[4:], (IAugustusV6.UniswapV2Data, uint256, bytes));
            beneficiary = uniswapV2Data.beneficiary;
            srcToken = uniswapV2Data.srcToken;
            destToken = uniswapV2Data.destToken;
            srcAmount = uniswapV2Data.fromAmount;
            quotedAmount = uniswapV2Data.quotedAmount;
        } else if (selector == IAugustusV6.swapExactAmountInOnUniswapV3.selector) {
            (IAugustusV6.UniswapV3Data memory uniswapV3Data,,) =
                abi.decode(data[4:], (IAugustusV6.UniswapV3Data, uint256, bytes));
            beneficiary = uniswapV3Data.beneficiary;
            srcToken = uniswapV3Data.srcToken;
            destToken = uniswapV3Data.destToken;
            srcAmount = uniswapV3Data.fromAmount;
            quotedAmount = uniswapV3Data.quotedAmount;
        } else {
            revert InvalidSelector();
        }

        if (beneficiary != YnUSDx && beneficiary != address(0)) {
            revert InvalidBeneficiary();
        }

        if (!supportedTokens[address(srcToken)] || !supportedTokens[address(destToken)]) {
            revert InvalidToken();
        }

        uint256 srcTokenRate = IProvider(provider).getRate(address(srcToken));
        uint256 destTokenRate = IProvider(provider).getRate(address(destToken));
        uint256 srcTokenDecimals = ERC20(address(srcToken)).decimals();
        uint256 destTokenDecimals = ERC20(address(destToken)).decimals();

        // Calculate expected amount without slippage first (convert from srcToken to destToken)
        uint256 expectedQuotedAmountWithoutSlippage = (srcAmount * srcTokenRate) / destTokenRate;

        if (srcTokenDecimals > destTokenDecimals) {
            expectedQuotedAmountWithoutSlippage =
                expectedQuotedAmountWithoutSlippage / 10 ** (srcTokenDecimals - destTokenDecimals);
        } else {
            expectedQuotedAmountWithoutSlippage =
                expectedQuotedAmountWithoutSlippage * 10 ** (destTokenDecimals - srcTokenDecimals);
        }

        // Then apply maximum slippage to get minimum required amount
        uint256 minRequiredQuotedAmount =
            (expectedQuotedAmountWithoutSlippage * (SLIPPAGE_PRECISION - maxSlippage)) / SLIPPAGE_PRECISION;

        if (quotedAmount < minRequiredQuotedAmount) {
            revert SlippageTooHigh();
        }
    }
}

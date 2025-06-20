// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {
    ParaswapValidator,
    InvalidTarget,
    InvalidValue,
    InvalidYnUSDx,
    InvalidToken,
    InvalidBeneficiary,
    SlippageTooHigh,
    InvalidSelector
} from "src/validator/ParaswapValidator.sol";
import {IAugustusV6} from "src/interface/IAugustusV6.sol";
import {IProvider} from "src/interface/IProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockERC20} from "lib/forge-std/src/mocks/MockERC20.sol";

contract MockProvider is IProvider {
    mapping(address => uint256) private rates;

    function setRate(address token, uint256 rate) external {
        rates[token] = rate;
    }

    function getRate(address token) external view returns (uint256) {
        return rates[token];
    }
}

contract ParaswapValidatorTest is Test {
    ParaswapValidator public validator;
    IERC20 public srcToken;
    IERC20 public destToken;
    MockProvider public provider;
    address public paraswapAugustus;
    address public ynUSDx;
    uint256 public maxSlippage;
    address[] public supportedTokens;

    function setUp() public {
        // Deploy mock tokens
        srcToken = IERC20(address(new MockERC20()));
        destToken = IERC20(address(new MockERC20()));

        // Deploy mock provider
        provider = new MockProvider();

        // Setup other parameters
        paraswapAugustus = makeAddr("paraswapAugustus");
        ynUSDx = makeAddr("ynUSDx");
        maxSlippage = 20; // 0.2% slippage

        // Setup supported tokens
        supportedTokens = new address[](2);
        supportedTokens[0] = address(srcToken);
        supportedTokens[1] = address(destToken);

        // Deploy validator
        validator = new ParaswapValidator(paraswapAugustus, ynUSDx, address(provider), maxSlippage, supportedTokens);

        // Setup provider rates
        provider.setRate(address(srcToken), 1e18);
        provider.setRate(address(destToken), 1e18);
    }

    function test_Validate_SwapExactAmountIn() public {
        uint256 srcAmount = 1000e18;
        uint256 toAmount = 990e18;
        uint256 quotedAmount = 999e18;

        IAugustusV6.GenericData memory swapData = IAugustusV6.GenericData({
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: toAmount,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: quotedAmount,
            metadata: bytes32(0)
        });

        bytes memory data = abi.encodeWithSelector(
            IAugustusV6.swapExactAmountIn.selector,
            makeAddr("executor"), // executor
            swapData,
            0, // partnerAndFee
            "", // permit
            "" // executorData
        );

        validator.validate(paraswapAugustus, 0, data);

        vm.expectRevert(InvalidTarget.selector);
        validator.validate(makeAddr("wrongTarget"), 0, data);

        vm.expectRevert(InvalidValue.selector);
        validator.validate(paraswapAugustus, 1, data);
    }

    function test_Validate_SwapExactAmountInOnCurveV1() public view {
        uint256 srcAmount = 1000e6;
        uint256 quotedAmount = 990e18;

        IAugustusV6.CurveV1Data memory curveV1Data = IAugustusV6.CurveV1Data({
            curveData: 0,
            curveAssets: 0,
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: quotedAmount,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: quotedAmount,
            metadata: bytes32(0)
        });

        bytes memory data = abi.encodeWithSelector(
            IAugustusV6.swapExactAmountInOnCurveV1.selector,
            curveV1Data,
            0, // partnerAndFee
            "" // permit
        );

        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_SwapExactAmountInOnCurveV2() public {
        uint256 srcAmount = 1000e6;
        uint256 quotedAmount = 990e18;

        IAugustusV6.CurveV2Data memory curveV2Data = IAugustusV6.CurveV2Data({
            curveData: 0,
            i: 0,
            j: 1,
            poolAddress: makeAddr("poolAddress"),
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: quotedAmount,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: quotedAmount,
            metadata: bytes32(0)
        });

        bytes memory data = abi.encodeWithSelector(
            IAugustusV6.swapExactAmountInOnCurveV2.selector,
            curveV2Data,
            0, // partnerAndFee
            "" // permit
        );

        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_SwapExactAmountInOnUniswapV2() public view {
        uint256 srcAmount = 1000e6;
        uint256 quotedAmount = 990e18;

        IAugustusV6.UniswapV2Data memory uniswapV2Data = IAugustusV6.UniswapV2Data({
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: quotedAmount,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: quotedAmount,
            metadata: bytes32(0),
            pools: new bytes(0)
        });

        bytes memory data = abi.encodeWithSelector(
            IAugustusV6.swapExactAmountInOnUniswapV2.selector,
            uniswapV2Data,
            0, // partnerAndFee
            "" // permit
        );

        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_SwapExactAmountInOnUniswapV3() public view {
        uint256 srcAmount = 1000e6;
        uint256 quotedAmount = 990e18;

        IAugustusV6.UniswapV3Data memory uniswapV3Data = IAugustusV6.UniswapV3Data({
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: quotedAmount,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: quotedAmount,
            metadata: bytes32(0),
            pools: new bytes(0)
        });

        bytes memory data = abi.encodeWithSelector(
            IAugustusV6.swapExactAmountInOnUniswapV3.selector,
            uniswapV3Data,
            0, // partnerAndFee
            "" // permit
        );

        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_RevertInvalidValue() public {
        bytes memory data = abi.encodeWithSelector(IAugustusV6.swapExactAmountIn.selector);
        vm.expectRevert(InvalidValue.selector);
        validator.validate(paraswapAugustus, 1, data);
    }

    function test_Validate_RevertInvalidTarget() public {
        bytes memory data = abi.encodeWithSelector(IAugustusV6.swapExactAmountIn.selector);
        vm.expectRevert(InvalidTarget.selector);
        validator.validate(makeAddr("wrongTarget"), 0, data);
    }

    function test_Validate_RevertInvalidToken() public {
        IERC20 unsupportedToken = IERC20(address(new MockERC20()));

        IAugustusV6.GenericData memory swapData = IAugustusV6.GenericData({
            srcToken: unsupportedToken,
            destToken: destToken,
            fromAmount: 1000e18,
            toAmount: 990e18,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: 990e18,
            metadata: bytes32(0)
        });

        bytes memory data =
            abi.encodeWithSelector(IAugustusV6.swapExactAmountIn.selector, address(0), swapData, 0, "", "");

        vm.expectRevert(InvalidToken.selector);
        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_RevertSlippageTooHigh() public {
        uint256 srcAmount = 1000e18;
        uint256 quotedAmount = 997e18; // 0.3% less than expected, exceeding max slippage

        IAugustusV6.GenericData memory swapData = IAugustusV6.GenericData({
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: quotedAmount,
            beneficiary: payable(address(ynUSDx)),
            quotedAmount: quotedAmount,
            metadata: bytes32(0)
        });

        bytes memory data =
            abi.encodeWithSelector(IAugustusV6.swapExactAmountIn.selector, address(0), swapData, 0, "", "");

        vm.expectRevert(SlippageTooHigh.selector);
        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_RevertInvalidBeneficiary() public {
        uint256 srcAmount = 1000e18;
        uint256 quotedAmount = 999e18;

        IAugustusV6.GenericData memory swapData = IAugustusV6.GenericData({
            srcToken: srcToken,
            destToken: destToken,
            fromAmount: srcAmount,
            toAmount: quotedAmount,
            beneficiary: payable(makeAddr("invalidBeneficiary")),
            quotedAmount: quotedAmount,
            metadata: bytes32(0)
        });

        bytes memory data =
            abi.encodeWithSelector(IAugustusV6.swapExactAmountIn.selector, address(0), swapData, 0, "", "");

        vm.expectRevert(InvalidBeneficiary.selector);
        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_InvalidYnUSDx() public {
        validator = new ParaswapValidator(paraswapAugustus, address(0), address(provider), maxSlippage, supportedTokens);

        bytes memory data = abi.encodeWithSelector(IAugustusV6.swapExactAmountIn.selector);
        vm.expectRevert(InvalidYnUSDx.selector);
        validator.validate(paraswapAugustus, 0, data);
    }

    function test_Validate_RevertInvalidSelector() public {
        bytes memory data = abi.encodeWithSelector(bytes4(0));
        vm.expectRevert(InvalidSelector.selector);
        validator.validate(paraswapAugustus, 0, data);
    }
}

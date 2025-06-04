// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// AugustusV6.2 interface taken from Paraswap docs(https://developers.paraswap.network/augustus-swapper/augustus-v6.2)
interface IAugustusV6 {
    /*//////////////////////////////////////////////////////////////
                        GENERIC SWAP DATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct containg data for generic swapExactAmountIn/swapExactAmountOut
    /// @param srcToken The token to swap from
    /// @param destToken The token to swap to
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount of destToken to receive
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param quotedAmount The quoted expected amount of destToken/srcToken
    /// = quotedAmountOut for swapExactAmountIn and quotedAmountIn for swapExactAmountOut
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiary The address to send the swapped tokens to
    struct GenericData {
        IERC20 srcToken;
        IERC20 destToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 quotedAmount;
        bytes32 metadata;
        address payable beneficiary;
    }

    /*//////////////////////////////////////////////////////////////
                            UNISWAPV2
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for UniswapV2 swapExactAmountIn/swapExactAmountOut data
    /// @param srcToken The token to swap from
    /// @param destToken The token to swap to
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param quotedAmount The quoted expected amount of destToken/srcToken
    /// = quotedAmountOut for swapExactAmountIn and quotedAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount of destToken to receive
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiary The address to send the swapped tokens to
    /// @param pools data consisting of concatenated token0 and token1 address for each pool with the direction flag being
    /// the right most bit of the packed token0-token1 pair bytes used in the path
    struct UniswapV2Data {
        IERC20 srcToken;
        IERC20 destToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 quotedAmount;
        bytes32 metadata;
        address payable beneficiary;
        bytes pools;
    }

    /*//////////////////////////////////////////////////////////////
                            UNISWAPV3
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for UniswapV3 swapExactAmountIn/swapExactAmountOut data
    /// @param srcToken The token to swap from
    /// @param destToken The token to swap to
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param quotedAmount The quoted expected amount of destToken/srcToken
    /// = quotedAmountOut for swapExactAmountIn and quotedAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount of destToken to receive
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiary The address to send the swapped tokens to
    /// @param pools data consisting of concatenated token0-
    /// token1-fee bytes for each pool used in the path, with the direction flag being the left most bit of token0 in the
    /// concatenated bytes
    struct UniswapV3Data {
        IERC20 srcToken;
        IERC20 destToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 quotedAmount;
        bytes32 metadata;
        address payable beneficiary;
        bytes pools;
    }

    /*//////////////////////////////////////////////////////////////
                            CURVE V1
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for CurveV1 swapExactAmountIn data
    /// @param curveData Packed data for the Curve pool, first 160 bits is the target exchange address,
    /// the 161st bit is the approve flag, bits from (162 - 163) are used for the wrap flag,
    //// bits from (164 - 165) are used for the swapType flag and the last 91 bits are unused:
    /// Approve Flag - a) 0 -> do not approve b) 1 -> approve
    /// Wrap Flag - a) 0 -> do not wrap b) 1 -> wrap native & srcToken == eth
    /// c) 2 -> unwrap and destToken == eth d) 3 - >srcToken == eth && do not wrap
    /// Swap Type Flag -  a) 0 -> EXCHANGE b) 1 -> EXCHANGE_UNDERLYING
    /// @param curveAssets Packed uint128 index i and uint128 index j of the pool
    /// The first 128 bits is the index i and the second 128 bits is the index j
    /// @param srcToken The token to swap from
    /// @param destToken The token to swap to
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount that must be recieved
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param quotedAmount The expected amount of destToken to be recieved
    /// = quotedAmountOut for swapExactAmountIn and quotedAmountIn for swapExactAmountOut
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiary The address to send the swapped tokens to
    struct CurveV1Data {
        uint256 curveData;
        uint256 curveAssets;
        IERC20 srcToken;
        IERC20 destToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 quotedAmount;
        bytes32 metadata;
        address payable beneficiary;
    }

    /*//////////////////////////////////////////////////////////////
                            CURVE V2
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for CurveV2 swapExactAmountIn data
    /// @param curveData Packed data for the Curve pool, first 160 bits is the target exchange address,
    /// the 161st bit is the approve flag, bits from (162 - 163) are used for the wrap flag,
    //// bits from (164 - 165) are used for the swapType flag and the last 91 bits are unused
    /// Approve Flag - a) 0 -> do not approve b) 1 -> approve
    /// Approve Flag - a) 0 -> do not approve b) 1 -> approve
    /// Wrap Flag - a) 0 -> do not wrap b) 1 -> wrap native & srcToken == eth
    /// c) 2 -> unwrap and destToken == eth d) 3 - >srcToken == eth && do not wrap
    /// Swap Type Flag -  a) 0 -> EXCHANGE b) 1 -> EXCHANGE_UNDERLYING c) 2 -> EXCHANGE_UNDERLYING_FACTORY_ZAP
    /// @param i The index of the srcToken
    /// @param j The index of the destToken
    /// The first 128 bits is the index i and the second 128 bits is the index j
    /// @param poolAddress The address of the CurveV2 pool (only used for EXCHANGE_UNDERLYING_FACTORY_ZAP)
    /// @param srcToken The token to swap from
    /// @param destToken The token to swap to
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount that must be recieved
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param quotedAmount The expected amount of destToken to be recieved
    /// = quotedAmountOut for swapExactAmountIn and quotedAmountIn for swapExactAmountOut
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiary The address to send the swapped tokens to
    struct CurveV2Data {
        uint256 curveData;
        uint256 i;
        uint256 j;
        address poolAddress;
        IERC20 srcToken;
        IERC20 destToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 quotedAmount;
        bytes32 metadata;
        address payable beneficiary;
    }

    /*//////////////////////////////////////////////////////////////
                            BALANCER V2
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for BalancerV2 swapExactAmountIn data
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount of destToken to receive
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param quotedAmount The quoted expected amount of destToken/srcToken
    /// = quotedAmountOut for swapExactAmountIn and quotedAmountIn for swapExactAmountOut
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiaryAndApproveFlag The beneficiary address and approve flag packed into one uint256,
    /// the first 20 bytes are the beneficiary address and the left most bit is the approve flag
    struct BalancerV2Data {
        uint256 fromAmount;
        uint256 toAmount;
        uint256 quotedAmount;
        bytes32 metadata;
        uint256 beneficiaryAndApproveFlag;
    }

    /*//////////////////////////////////////////////////////////////
                            MAKERPSM
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for Maker PSM swapExactAmountIn data
    /// @param srcToken The token to swap from
    /// @param destToken The token to swap to
    /// @param fromAmount The amount of srcToken to swap
    /// = amountIn for swapExactAmountIn and maxAmountIn for swapExactAmountOut
    /// @param toAmount The minimum amount of destToken to receive
    /// = minAmountOut for swapExactAmountIn and amountOut for swapExactAmountOut
    /// @param toll Used to calculate gem amount for the swapExactAmountIn
    /// @param to18ConversionFactor Used to calculate gem amount for the swapExactAmountIn
    /// @param gemJoinAddress The address of the gemJoin contract
    /// @param exchange The address of the exchange contract
    /// @param metadata Packed uuid and additional metadata
    /// @param beneficiaryDirectionApproveFlag The beneficiary address, swap direction and approve flag packed
    /// into one uint256, the first 20 bytes are the beneficiary address, the left most bit is the approve flag and the
    /// second left most bit is the swap direction flag, 0 for swapExactAmountIn and 1 for swapExactAmountOut
    struct MakerPSMData {
        IERC20 srcToken;
        IERC20 destToken;
        uint256 fromAmount;
        uint256 toAmount;
        uint256 toll;
        uint256 to18ConversionFactor;
        address exchange;
        address gemJoinAddress;
        bytes32 metadata;
        uint256 beneficiaryDirectionApproveFlag;
    }

    /// @notice Executes a generic swapExactAmountIn using the given executorData on the given executor
    /// @param executor The address of the executor contract to use
    /// @param swapData Generic data containing the swap information
    /// @param partnerAndFee packed partner address and fee percentage, the first 12 bytes is the feeData and the last
    /// 20 bytes is the partner address
    /// @param permit The permit data
    /// @param executorData The data to execute on the executor
    /// @return receivedAmount The amount of destToken received after fees
    /// @return paraswapShare The share of the fees for Paraswap
    /// @return partnerShare The share of the fees for the partner
    function swapExactAmountIn(
        address executor,
        GenericData calldata swapData,
        uint256 partnerAndFee,
        bytes calldata permit,
        bytes calldata executorData
    ) external payable returns (uint256 receivedAmount, uint256 paraswapShare, uint256 partnerShare);

    /// @notice Executes a swapExactAmountIn on Balancer V2 pools
    /// @param balancerData Struct containing data for the swap
    /// @param partnerAndFee packed partner address and fee percentage, the first 12 bytes is the feeData and the last
    /// 20 bytes is the partner address
    /// @param permit Permit data for the swap
    /// @param data The calldata to execute
    /// the first 20 bytes are the beneficiary address and the left most bit is the approve flag
    /// @return receivedAmount The amount of destToken received after fees
    /// @return paraswapShare The share of the fees for Paraswap
    /// @return partnerShare The share of the fees for the partner
    function swapExactAmountInOnBalancerV2(
        BalancerV2Data calldata balancerData,
        uint256 partnerAndFee,
        bytes calldata permit,
        bytes calldata data
    ) external payable returns (uint256 receivedAmount, uint256 paraswapShare, uint256 partnerShare);

    /// @notice Executes a swapExactAmountIn on Curve V1 pools
    /// @param curveV1Data Struct containing data for the swap
    /// @param partnerAndFee packed partner address and fee percentage, the first 12 bytes is the feeData and the last
    /// 20 bytes is the partner address
    /// @param permit Permit data for the swap
    /// @return receivedAmount The amount of destToken received after fees
    /// @return paraswapShare The share of the fees for Paraswap
    /// @return partnerShare The share of the fees for the partner
    function swapExactAmountInOnCurveV1(CurveV1Data calldata curveV1Data, uint256 partnerAndFee, bytes calldata permit)
        external
        payable
        returns (uint256 receivedAmount, uint256 paraswapShare, uint256 partnerShare);

    /// @notice Executes a swapExactAmountIn on Curve V2 pools
    /// @param curveV2Data Struct containing data for the swap
    /// @param partnerAndFee packed partner address and fee percentage, the first 12 bytes is the feeData and the last
    /// 20 bytes is the partner address
    /// @param permit Permit data for the swap
    /// @return receivedAmount The amount of destToken received after fees
    /// @return paraswapShare The share of the fees for Paraswap
    /// @return partnerShare The share of the fees for the partner
    function swapExactAmountInOnCurveV2(CurveV2Data calldata curveV2Data, uint256 partnerAndFee, bytes calldata permit)
        external
        payable
        returns (uint256 receivedAmount, uint256 paraswapShare, uint256 partnerShare);

    /// @notice Executes a swapExactAmountIn on Uniswap V2 pools
    /// @param uniData struct containing data for the swap
    /// @param partnerAndFee packed partner address and fee percentage, the first 12 bytes is the feeData and the last
    /// 20 bytes is the partner address
    /// @param permit The permit data
    /// @return receivedAmount The amount of destToken received after fees
    /// @return paraswapShare The share of the fees for Paraswap
    /// @return partnerShare The share of the fees for the partner
    function swapExactAmountInOnUniswapV2(UniswapV2Data calldata uniData, uint256 partnerAndFee, bytes calldata permit)
        external
        payable
        returns (uint256 receivedAmount, uint256 paraswapShare, uint256 partnerShare);

    /// @notice Executes a swapExactAmountIn on Uniswap V3 pools
    /// @param uniData struct containing data for the swap
    /// @param partnerAndFee packed partner address and fee percentage, the first 12 bytes is the feeData and the last
    /// 20 bytes is the partner address
    /// @param permit The permit data
    /// @return receivedAmount The amount of destToken received after fees
    /// @return paraswapShare The share of the fees for Paraswap
    /// @return partnerShare The share of the fees for the partner
    function swapExactAmountInOnUniswapV3(UniswapV3Data calldata uniData, uint256 partnerAndFee, bytes calldata permit)
        external
        payable
        returns (uint256 receivedAmount, uint256 paraswapShare, uint256 partnerShare);
}

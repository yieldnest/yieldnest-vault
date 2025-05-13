// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IStakerGateway {
    /* Events
    ***********************************************************************************************************/

    /// An asset was staked
    event AssetStaked(address indexed staker, address indexed asset, uint256 amount, string indexed referralId);

    /// An asset was unstaked
    event AssetUnstaked(address indexed staker, address indexed asset, uint256 amount, string indexed referralId);

    /* Errors
    ***********************************************************************************************************/

    /// Contract couldn't receive native tokens
    error CannotReceiveNativeTokens();

    /// Function argument was invalid
    error InvalidArgument(string);

    /// The unstaking failed
    error UnstakeFailed(string);

    /* External Functions
    ***********************************************************************************************/

    function initialize(address configAddr) external;

    function balanceOf(address asset, address owner) external view returns (uint256);

    function getVault(address asset) external view returns (address);

    function stake(address asset, uint256 amount, string calldata referralId) external;

    function stakeClisBNB(string calldata referralId) external payable;

    function stakeNative(string calldata referralId) external payable;

    function unstake(address asset, uint256 amount, string calldata referralId) external;

    function unstakeClisBNB(uint256 amount, string calldata referralId) external;

    function unstakeNative(uint256 amount, string calldata referralId) external;

    function getConfig() external view returns (address);
}

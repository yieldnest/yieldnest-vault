// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

interface IKernelVault {
    /* Events
    ***********************************************************************************************************/

    // Deposit Limit of vault has changed
    event DepositLimitChanged(uint256 newLimit);

    /* Errors
    ***********************************************************************************************************/

    /// The Deposit failed
    error DepositFailed(string);

    /// The Deposit failed because the limit was exceeded
    /// @param depositAmount the amount to deposit
    /// @param depositLimit the limit exceeded
    error DepositLimitExceeded(uint256 depositAmount, uint256 depositLimit);

    /// A function was called by an unauthorized sender
    error UnauthorizedCaller(address);

    /// The withdraw failed
    error WithdrawFailed(string);

    /* External Functions
    ***********************************************************************************************/

    function balance() external view returns (uint256);

    function balanceERC20() external view returns (uint256);

    function balanceOf(address address_) external view returns (uint256);

    function deposit(uint256 vaultBalanceBefore, address owner) external returns (uint256);

    function getAsset() external view returns (address);

    function getDecimals() external view returns (uint8);

    function getDepositLimit() external view returns (uint256);

    function initialize(address assetAddr, address configAddr) external;

    function setDepositLimit(uint256 limit) external;

    function withdraw(uint256 amount, address owner, bool approveSender) external;

    function getConfig() external view returns (address);
}

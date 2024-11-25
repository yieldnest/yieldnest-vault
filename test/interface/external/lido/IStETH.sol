// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface IStETH {
    function submit(address _referral) external payable returns (uint256);

    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    function getSharesByPooledEth(uint256 _pooledEthAmount) external view returns (uint256);
}

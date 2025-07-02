// SPDX-License-Identifier: BSD 3-Clause License
pragma solidity ^0.8.24;

import "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRedeemableAsset is IERC20Metadata {
    function burn(uint256 amount) external;
    function processWithdrawnETH() external payable;
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

// https://github.com/lidofinance/lido-dao/blob/master/contracts/0.4.24/StETH.sol
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockSTETH is ERC20 {
    uint256 private _pooledEthPerShare = 1e18; // Start with 1:1 ratio
    mapping(address => uint256) public shares;

    constructor() ERC20("Mock Staked Ether", "mstETH") {}

    function getSharesByPooledEth(uint256 amount) internal pure returns (uint256) {
        return (amount * 98e16) / 1e18;
    }

    function deposit() public payable {
        uint256 depostShares = getSharesByPooledEth(msg.value);
        _mint(msg.sender, depostShares);
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return getPooledEthByShares(_sharesOf(_account));
    }

    function getPooledEthByShares(uint256 _sharesAmount) internal view returns (uint256) {
        return (_sharesAmount * _pooledEthPerShare) / 1e18;
    }

    function _sharesOf(address _account) internal view returns (uint256) {
        return shares[_account];
    }

    receive() external payable {
        deposit();
    }
}

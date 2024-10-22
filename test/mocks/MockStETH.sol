// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

// https://github.com/lidofinance/lido-dao/blob/master/contracts/0.4.24/StETH.sol
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MockStETH is ERC20 {
    uint256 private _pooledEthPerShare = 1e18; // Start with 1:1 ratio

    constructor() ERC20("Mock Staked Ether", "mstETH") {
        _mint(msg.sender, 1000000 * 10 ** 18); // Mint 1 million tokens
    }

    function deposit(uint256 amount) public {
        _mint(msg.sender, amount);
    }

    // function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256) {
    //     return (_sharesAmount * _pooledEthPerShare) / 1e18;
    // }

    // // Function to simulate stETH price changes
    // function setPooledEthPerShare(uint256 newRatio) external {
    //     _pooledEthPerShare = newRatio;
    // }

    // function balanceOf(address _account) public view returns (uint256) {
    //     return getPooledEthByShares(_sharesOf(_account));
    // }

    // function _sharesOf(address _account) internal view returns (uint256) {
    //     return shares[_account];
    // }
}

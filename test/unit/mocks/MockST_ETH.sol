// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

// https://github.com/lidofinance/lido-dao/blob/master/contracts/0.4.24/StETH.sol
import {ERC20} from "src/Common.sol";
import {IStETH} from "src/interface/external/lido/IStETH.sol";

contract MockSTETH is IStETH, ERC20 {
    uint256 totalPooledEther;

    constructor() ERC20("Mock Staked Ether", "mstETH") {}

    function balanceOf(address _account) public view override(ERC20) returns (uint256) {
        return getPooledEthByShares(super.balanceOf(_account));
    }

    function getPooledEthByShares(uint256 _sharesAmount) public view override returns (uint256) {
        if (_getTotalShares() == 0) {
            return _sharesAmount;
        }
        return _sharesAmount * _getTotalPooledEther() / _getTotalShares();
    }

    function getSharesByPooledEth(uint256 _pooledEthAmount) public view override returns (uint256) {
        if (_getTotalPooledEther() == 0) {
            return _pooledEthAmount;
        }
        return _pooledEthAmount * _getTotalShares() / _getTotalPooledEther();
    }

    function totalSupply() public view override(ERC20) returns (uint256) {
        return _getTotalPooledEther();
    }

    function _getTotalShares() internal view returns (uint256) {
        return super.totalSupply();
    }

    function _getTotalPooledEther() internal view returns (uint256) {
        return totalPooledEther;
    }

    function submit(address /*_referral*/ ) public payable override returns (uint256) {
        require(msg.value != 0, "ZERO_DEPOSIT");
        uint256 sharesAmount = getSharesByPooledEth(msg.value);
        _mint(msg.sender, sharesAmount);

        totalPooledEther += msg.value;
        return sharesAmount;
    }

    function deposit() public payable returns (uint256) {
        return submit(address(0));
    }

    receive() external payable {
        submit(address(0));
    }

    // Add rewards to simulate staking rewards being added to the pool
    function addRewards() public payable {
        require(msg.value > 0, "Must send ETH");
        // Increase total pooled ether without minting new shares
        totalPooledEther += msg.value;
    }
}

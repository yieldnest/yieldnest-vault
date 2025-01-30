// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MockStakeHub {
    error NoStake();
    error FailedToSendEther();

    mapping(address => uint256) public staked;

    function stake() external payable {
        staked[msg.sender] += msg.value;
    }

    function claim(address _validator, uint256) external {
        if (staked[_validator] == 0) {
            revert NoStake();
        }
        (bool success,) = payable(msg.sender).call{value: staked[_validator]}("");
        if (!success) {
            revert FailedToSendEther();
        }
        staked[_validator] = 0;
    }

    function getValidatorCreditContract(address) external view returns (address) {
        return address(this);
    }

    function getSharesByPooledBNB(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getPooledBNBByShares(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function undelegate(address, uint256) external {}
}

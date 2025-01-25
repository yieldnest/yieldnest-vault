// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

contract MockStakeHub {
    mapping(address => uint256) public staked;

    function stake() external payable {
        staked[msg.sender] += msg.value;
    }

    function claim(address _validator, uint256) external {
        require(staked[_validator] > 0, "no stake");
        (bool success,) = payable(msg.sender).call{value: staked[_validator]}("");
        if (!success) {
            revert("failed to send ether");
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

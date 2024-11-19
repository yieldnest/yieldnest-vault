// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {IStrategy} from "src/interface/IStrategy.sol";
import {IERC20, ERC20} from "src/Common.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract MockBuffer is ERC20 {
    // Implement the interface functions here
    address private _asset;
    uint256 private _totalAssets;

    mapping(address => uint256) public balances;

    event Deposit(address indexed sender, address indexed receiver, uint256 amount, uint256 totalAssets);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    constructor() ERC20("Mock Buffer", "BUFF") {
        _asset = MC.WETH;
        _totalAssets = 0;
    }

    function deposit(uint256 assets, address receiver) public returns (uint256) {
        balances[receiver] += assets;
        _totalAssets += assets;
        IERC20(MC.WETH).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, assets);
        emit Deposit(msg.sender, receiver, assets, assets);
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) public returns (uint256) {
        require(balances[owner] >= assets, "Insufficient balance");
        balances[owner] -= assets;
        _totalAssets -= assets;

        IERC20(MC.WETH).transferFrom(address(this), receiver, assets);
        _burn(owner, assets);
        emit Withdraw(msg.sender, receiver, owner, assets, assets);
        return assets;
    }

    function mint(uint256 shares, address receiver) public returns (uint256) {
        balances[receiver] += shares;
        _totalAssets += convertToAssets(shares);
        emit Deposit(msg.sender, receiver, shares, shares);
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) public returns (uint256) {
        require(balances[owner] >= shares, "Insufficient balance");
        balances[owner] -= shares;
        uint256 bufferAssets = convertToAssets(shares);
        _totalAssets -= bufferAssets;
        IERC20(MC.WETH).transferFrom(address(this), owner, bufferAssets);
        emit Withdraw(msg.sender, receiver, owner, bufferAssets, shares);
        return shares;
    }

    function asset() public view returns (address) {
        return _asset;
    }

    function totalAssets() public view returns (uint256) {
        return _totalAssets;
    }

    function convertToShares(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    function convertToAssets(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    function maxDeposit(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view returns (uint256) {
        return balances[owner];
    }

    function maxRedeem(address owner) public view returns (uint256) {
        return balances[owner];
    }

    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    function previewMint(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    function previewWithdraw(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    function previewRedeem(uint256 shares) public pure returns (uint256) {
        return shares;
    }

    function transferFrom(address owner, address spender, uint256 value) public override returns (bool) {
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= value, "ERC20: insufficient allowance");
        unchecked {
            _approve(owner, spender, currentAllowance - value);
        }
        _transfer(owner, spender, value);
        return true;
    }
}

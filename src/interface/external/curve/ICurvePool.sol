// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface ICurvePool {
    function add_liquidity(uint256[] memory _amounts, uint256 _min_mint_amount) external returns (uint256);
    function remove_liquidity_one_coin(uint256 _burn_amount, int128 i, uint256 _min_received, address _receiver)
        external
        returns (uint256);
    function get_balances() external view returns (uint256[] memory);
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function coins(uint256 i) external view returns (address);
    function remove_liquidity(uint256 _amount, uint256[] memory min_amounts, address receiver)
        external
        returns (uint256[2] memory);
    function get_virtual_price() external view returns (uint256);
    function lp_price() external view returns (uint256);
    function name() external view returns (string memory);
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
}

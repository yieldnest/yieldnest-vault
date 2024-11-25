// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

interface ICurveRegistry {
    function get_pool_from_lp_token(address lp_token) external view returns (address);
    function find_pool_for_coins(address from, address to) external view returns (address);
    function find_pool_for_coins(address from, address to, uint256 i) external view returns (address);
    function get_lp_token(address pool) external view returns (address);
    function get_n_coins(address pool) external view returns (uint256);
    function get_coins(address pool) external view returns (address[8] memory);
    function get_underlying_coins(address pool) external view returns (address[8] memory);
    function get_decimals(address pool) external view returns (uint256[8] memory);
    function get_underlying_decimals(address pool) external view returns (uint256[8] memory);
    function get_rates(address pool) external view returns (uint256[8] memory);
    function get_gauges(address pool) external view returns (address[10] memory, int128[10] memory);
    function get_balances(address pool) external view returns (uint256[8] memory);
    function get_underlying_balances(address pool) external view returns (uint256[8] memory);
    function get_virtual_price_from_lp_token(address lp_token) external view returns (uint256);
    function get_A(address pool) external view returns (uint256);
    function get_fees(address pool) external view returns (uint256[2] memory);
    function get_admin_balances(address pool) external view returns (uint256[8] memory);
}

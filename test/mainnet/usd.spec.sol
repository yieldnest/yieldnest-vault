// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

// valid concern

// https://etherscan.io/address/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48#readProxyContract

// USDC has 6 decimals. so does USDT and Paypal USD etc.

// We'll have to decide what ynUSDx has - i'd go for 18 like DAI, Ethena and the Defi Stables. It would still work to have our vaults have 18 decimals and assets with different decimals so it

// Something to research: do we break ERC4626 if asset() has 6 decimals and The Vault has 18? that may impact our choice of base asset

// I noticed one gotcha here though:

// https://github.com/OpenZeppelin/openzeppelin-contracts-upgradeable/blob/723f8cab09cdae1aca9ec9cc1cfa040c2d4b06c1/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol#L98C30-L98C43

// OZ default ERC4626 implementation takes the decimal count from whatever you configure as the asset

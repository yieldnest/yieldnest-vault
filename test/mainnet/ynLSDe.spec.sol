// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

// converts 50 ETH to stETH and allocates it to ynLSDE

// we have to handle the asynchronous withdrawal positions for certain strategies with custom logic for ynETH and ynLSDe and potentially other asynchronous withdrawals strategies.

// For ynETH and ynLSDe, you'd call

// withdrawalRequestsForOwner
// https://github.com/yieldnest/yieldnest-protocol/blob/main/src/WithdrawalQueueManager.sol#L561
// and sum the WithdrawalRequest.amount

// Going into this, there was the idea of packaging karak in an ynLSDk asset on its own. That still makes sense since you have to not only handle staking/unstaking but also operator selection and create multiple vaults per asset. With karak you create one vault per validator(?). with ynLSDk we would then control the withdrawal interface.

// Regardless, It seems like here we'd need the custom module/modules functionality to handle withdrawal positions. In theory this way you could plug in other protocols as well as strategies (Eg. you can plug in WEETH as a tokenized strategy).

## ynETH MAX Starter Vault

This is a general purpose 4626 starter vault for rapid deployment against new opportunies.

## Overview

The initial version is a SingleAsset 4626 Vault with TimelockController to send Admin transactions.
This vault is the Base version used for pre-depositing assets ahead of settled DeFi functionality.

Please see the 4626 documentation at: https://docs.openzeppelin.com/contracts/5.x/erc4626

## Testing

```
make unit-test
make holeksy-test
make mainnet-test
```

## Contract Deployments

### Mainnet
| Name | Address |
|-----------------------|------------------------------------------------|
| ynETHx                | [0x657d9ABA1DBb59e53f9F3eCAA878447dCfC96dCb](https://etherscan.io/address/0x657d9ABA1DBb59e53f9F3eCAA878447dCfC96dCb)   				 	 |
| WETH             			| [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2](https://etherscan.com/address/0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)   					 |
| Timelock							| [0xb5b52c63067E490982874B0d0F559668Bbe0c36B](https://etherscan.com/address/0xb5b52c63067E490982874B0d0F559668Bbe0c36B)						 |
| ProxyAdmin						| [0xA02A8DC24171aC161cCb74Ef02C28e3cA2204783](https://etherscan.io/address/0xA02A8DC24171aC161cCb74Ef02C28e3cA2204783)

### Holesky Testnet
| Name | Address |
|-----------------------|--------------------------------------------------------|
| ynETHx                | [0xfd930060e51C10CCBc36F512676B4FD3E7026a1E](https://holesky.etherscan.io/address/0xfd930060e51C10CCBc36F512676B4FD3E7026a1E)   				 	 |
| WETH             			| [0x94373a4919B3240D86eA41593D5eBa789FEF3848](https://holesky.etherscan.com/address/0x94373a4919B3240D86eA41593D5eBa789FEF3848)   					 |
| Timelock							| [0x8f4E6d1BfCd1e02aD775938C747e06beeF0c7Cb8](https://holesky.etherscan.com/address/0x8f4E6d1BfCd1e02aD775938C747e06beeF0c7Cb8)						 |
| ProxyAdmin						| [0x995B08478A19e0BfDb2232804A742477654120a0](https:///holesky.etherscan.com/address/0x995B08478A19e0BfDb2232804A742477654120a0)							|


# Project Deployment Commands
This README provides an overview of the commands used to deploy and interact with the smart contracts in this project. The commands are defined in the Makefile and utilize tools such as forge and cast.

## Commands

### Local Factory Deployment
Deploys the DeployVaultFactory script locally to port 8545 using a private key.
```
make local-factory
```

**Details:**
* Script: `script/DeployFactory.s.sol:DeployFactory`
* Options:
  + `--private-key $(PRIVATE_KEY)`: Uses the specified private key.
  + `--broadcast`: Broadcasts the transaction.

### Factory Deployment
Deploys the DeployVaultFactory script using an account name.
```
make factory
```
**Details:**
* Script: `script/DeployFactory.s.sol:DeployFactory`
* Options:
	+ `--account ${ACCOUNT_NAME}`: Uses the specified account name.
	+ `--rpc-url ${RPC_URL}`: Connects to the specified RPC URL.
	+ `--verify`: Verifies the contract on Etherscan.
	+ `--broadcast`: Broadcasts the transaction.

### Create Single Vault
Sends a transaction to create a single vault using the `createSingleVault` function.

**Details:**

* Function: `createSingleVault(address, string, string, address, uint256, address[], address[])`
* Arguments:
	+ `address _logic`: `${ASSET_ADDRESS}`
	+ `string _name`: `"${VAULT_NAME}"`
	+ `string _symbol`: `"${VAULT_SYMBOL}"`
	+ `address _admin`: `${ADMIN_ADDRESS}`
	+ `uint256 _minDelay`: `${MIN_DELAY}`
	+ `address[] _proposers`: `"[${PROPOSER_1}]"`
	+ `address[] _executors`: `"[${EXECUTOR_1}]"`
* Options:
	+ `--account ${ACCOUNT_NAME}`: Uses the specified account name.
	+ `--rpc-url ${RPC_URL}`: Connects to the specified RPC URL.

**Usage:**

To use these commands, ensure you have the necessary environment variables set:
```
export RPC_URL="your_rpc_url"
export ACCOUNT_NAME="your_account_name"
export FACTORY_ADDRESS="your_factory_address"
export ASSET_ADDRESS="your_asset_address"
export VAULT_NAME="your_vault_name"
export VAULT_SYMBOL="your_vault_symbol"
export ADMIN_ADDRESS="your_admin_address"
export MIN_DELAY="your_min_delay"
export PROPOSER_1="your_proposer_1"
export EXECUTOR_1="your_executor_1"


make vault
```

## Security Notes

There's a loss incurred by the user that's roughly less than `Max(amount, rewards) / 1e18` when he withdraws the exact same shares he received  when compared to what he deposited.

I believe this is  because of that decimal offset in OZ 46426Upgradeable to prevent donation attacks. The loss maxes out at 10000 wei for 10000 ether amounts so it's small.

1. Deposit Withdraw Scenario
There's a loss incurred by the user that's roughly less than `Max(amount, rewards) / 1e18` when he withdraws the exact same shares he received  when compared to what he deposited.

2. Infaltion Attack
OZ expalains mitigiation of this attach in v5 here: https://docs.openzeppelin.com/contracts/5.x/erc4626
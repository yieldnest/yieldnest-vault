## YieldNest Vault

This is a general purpose starter vault for rapid deployment against new opportunies.

## Overview

The initial version is a SingleAsset 4626 Vault with TimelockController to send Admin transactions.
This vault is the Base version used for pre-depositing assets ahead of settled DeFi functionality.

## Test Deployment

See the makefile for deployment scripts. Deploy a factory first, then use it to deploy a new vault.


## Contract Deployments

### BSC Mainnet
| Name | Address |
|-----------------------|----------------------------------------------|
| ynBNB                 | [0x304B5845b9114182ECb4495Be4C91a273b74B509](https://testnet.bscscan.com/address/0x304B5845b9114182ECb4495Be4C91a273b74B509)   |
| slisBNB               | [0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B](https://bscscan.com/address/0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B)   				|
| Vault Factory         | [0x8F74AC4a934Db365720fa4A0e7aE62FF2457DE41](https://bscscan.com/address/0x8f74ac4a934db365720fa4a0e7ae62ff2457de41)   				|
| VaultFactory Impl			| [0x53dd506c5fC655634F2ab7ca0c1801a08e0Cb607](https://bscscan.com/address/0x53dd506c5fc655634f2ab7ca0c1801a08e0cb607)					|
| SingleVault Imp       | [0x80815ee920Bd9d856562633C36D3eB0E43cb15e2](https://bscscan.com/address/0x80815ee920bd9d856562633c36d3eb0e43cb15e2)					|
| Timelock							| [0xd53044093F757E8a56fED3CCFD0AF5Ad67AeaD4a](https://bscscan.com/address/0xd53044093f757e8a56fed3ccfd0af5ad67aead4a)					|
| ProxyAdmin 						| [0x341932c52C431427c2d759f344a0C5085B0F4576](https://bscscan.com/address/0x341932c52c431427c2d759f344a0c5085b0f4576)					|
| Security Council			| [0x721688652DEa9Cabec70BD99411EAEAB9485d436](https://bscscan.com/address/0x721688652DEa9Cabec70BD99411EAEAB9485d436)					|

### BSC Testnet
| Name | Address |
|-----------------------|----------------------------------------------|
| ynBNB                 | [0x7e87787C22117374Fad2E3E2E8C6159f0875F92e](https://testnet.bscscan.com/address/0x7e87787c22117374fad2e3e2e8c6159f0875f92e)   |
| slisBNB               | [0x80815ee920Bd9d856562633C36D3eB0E43cb15e2](https://testnet.bscscan.com/address/0x80815ee920bd9d856562633c36d3eb0e43cb15e2)   |
| VaultFactory          | [0x964C6d4050e052D627b8234CAD9CdF0981E40EB3](https://testnet.bscscan.com/address/0x964C6d4050e052D627b8234CAD9CdF0981E40EB3)   |
| SingleVault           | [0xa2aE2b28c578Fbd7C18B554E7aA388Bf6694a42c](https://testnet.bscscan.com/address/0xa2aE2b28c578Fbd7C18B554E7aA388Bf6694a42c)   |


# Project Deployment Commands
This README provides an overview of the commands used to deploy and interact with the smart contracts in this project. The commands are defined in the Makefile and utilize tools such as forge and cast.

## Commands

### Local Factory Deployment
Deploys the DeployVaultFactory script locally to port 8545 using a private key.
```
make local-factory
```

**Details:**
* Script: `script/Deploy.s.sol:DeployVaultFactory`
* Options:
  + `--private-key $(PRIVATE_KEY)`: Uses the specified private key.
  + `--broadcast`: Broadcasts the transaction.

### Factory Deployment
Deploys the DeployVaultFactory script using an account name.
```
make deploy-factory
```
**Details:**
* Script: `script/Deploy.s.sol:DeployVaultFactory`
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
	+ `address[] _proposers`: `"[${PROPOSER_1},${PROPOSER_2}]"`
	+ `address[] _executors`: `"[${EXECUTOR_1},${EXECUTOR_2}]"`
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
export PROPOSER_2="your_proposer_2"
export EXECUTOR_1="your_executor_1"
export EXECUTOR_2="your_executor_2"


make single-vault
```

## Security Notes

There's a loss incurred by the user that's roughly less than `Max(amount, rewards) / 1e18` when he withdraws the exact same shares he received  when compared to what he deposited.

I believe this is  because of that decimal offset in OZ 46426Upgradeable to prevent donation attacks. The loss maxes out at 10000 wei for 10000 ether amounts so it's small.

1. Deposit Withdraw Scenario
There's a loss incurred by the user that's roughly less than `Max(amount, rewards) / 1e18` when he withdraws the exact same shares he received  when compared to what he deposited.

I believe this is  because of that decimal offset in OZ 46426Upgradeable to prevent donation attacks. The loss maxes out at 10000 wei for 10000 ether amounts so it's small.

2. Initial Version of the Vault is trusted by the YnBscSecurityCouncil:
https://app.safe.global/home?safe=bnb:0x721688652DEa9Cabec70BD99411EAEAB9485d436
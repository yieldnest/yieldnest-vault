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
| slisBNB               | [0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B](https://bscscan.com/address/0xB0b84D294e0C75A6abe60171b70edEb2EFd14A1B)   |
| VaultFactory          | [0xf6B9b69B7e13D37D3846698bA2625e404C7586aF](https://testnet.bscscan.com/address/0xf6B9b69B7e13D37D3846698bA2625e404C7586aF)   |
| SingleVault           | [0x40020796C11750975aD8758a1F2ab725f6b72Db2](https://testnet.bscscan.com/address/0x40020796C11750975aD8758a1F2ab725f6b72Db2)   |
| ynBNB                 | [](https://testnet.bscscan.com/address/)   |

### BSC Testnet
| Name | Address |
|-----------------------|----------------------------------------------|
| slisBNB               | [0x80815ee920Bd9d856562633C36D3eB0E43cb15e2](https://testnet.bscscan.com/address/0x80815ee920bd9d856562633c36d3eb0e43cb15e2)   |
| VaultFactory          | [0x964C6d4050e052D627b8234CAD9CdF0981E40EB3](https://testnet.bscscan.com/address/0x964C6d4050e052D627b8234CAD9CdF0981E40EB3)   |
| SingleVault           | [0xa2aE2b28c578Fbd7C18B554E7aA388Bf6694a42c](https://testnet.bscscan.com/address/0xa2aE2b28c578Fbd7C18B554E7aA388Bf6694a42c)   |
| ynBNB                 | [0x7e87787C22117374Fad2E3E2E8C6159f0875F92e](https://testnet.bscscan.com/address/0x7e87787c22117374fad2e3e2e8c6159f0875f92e)   |


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
## YieldNest Vault

This is a general purpose starter vault for rapid deployment against new opportunies.

## Overview

The initial version is a SingleAsset 4626 Vault with TimelockController to send Admin transactions.
This vault is the Base version used for pre-depositing assets ahead of settled DeFi functionality.

## Test Deployment

```
anvil // --fork-url https://holesky-rpc

export ACCOUNT_NAME=deployer
make account

export RPC_URL=
export ETHERSCAN_KEY=

make factory
```

This will deploy the factory, from which you can create a new vault.


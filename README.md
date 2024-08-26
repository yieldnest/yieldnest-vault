## YieldNest Vault


This is a general purpose starter vault for rapid deployment against new opportunies.

## Overview

The initial version is a SingleAsset 4626 vault that is a TimelockController to send arbitrary transactions.


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


#!/bin/bash

# Load environment variables
source .env

# Check if required environment variables are set
if [ -z "$RPC_URL" ] || [ -z "$ACCOUNT_NAME" ] || [ -z "$FACTORY_ADDRESS" ] || [ -z "$ASSET_ADDRESS" ] || [ -z "$VAULT_NAME" ] || [ -z "$VAULT_SYMBOL" ] || [ -z "$ADMIN_ADDRESS" ] || [ -z "$MIN_DELAY" ] || [ -z "$PROPOSER_1" ] || [ -z "$EXECUTOR_1" ]; then
  echo "One or more required environment variables are not set. Please check your .env file."
  exit 1
fi

# Create Single Vault
cast send $FACTORY_ADDRESS \
  "createSingleVault(address,string,string,address,uint256,address[],address[])" \
  $ASSET_ADDRESS "$VAULT_NAME" "$VAULT_SYMBOL" $ADMIN_ADDRESS $MIN_DELAY "[$PROPOSER_1]" "[$EXECUTOR_1]" \
  --account $ACCOUNT_NAME \
  --rpc-url $RPC_URL

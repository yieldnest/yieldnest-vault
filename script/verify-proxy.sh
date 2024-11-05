# This was the script used to verify the TransparentUpgradeableProxy on etherscan
PROXY_CONTRACT_TO_VERIFY=0x12aaa2e48b1f41a7e0a6a0729d09316d900bbb32

# NOTE: Get the constructor args from Etherscan. You can get this from the Verify and Publish section after it fails, it will tell you what it wants from the contract bytecode
# The last section of the byte code is the constructor. There seems to be a difference between how cast cosntructos abi-encoded data and how Etherscan does.
PROXY_CONSTRUCTOR_DATA=00000000000000000000000042930ea83754c11512259f14927a4e62b912f64e000000000000000000000000f4956c6ab6886a137740ad26107bc55cbc67b90000000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000084f8c8765e00000000000000000000000065558d7a8df7effe69c47f96d99856dae9d58dcc000000000000000000000000fcad670592a3b24869c0b51a6c6fded4f95d6975000000000000000000000000f4956c6ab6886a137740ad26107bc55cbc67b900000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc200000000000000000000000000000000000000000000000000000000


forge verify-contract $PROXY_CONTRACT_TO_VERIFY \
  --constructor-args $PROXY_CONSTRUCTOR_DATA \
  --num-of-optimizations 200 \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --rpc-url $RPC_URL \
  --watch
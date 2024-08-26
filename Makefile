

account :; cast wallet import $(ACCOUNT_NAME) --interactive

factory :; forge script script/DeployVaultFactory.sol:DeployVaultFactory \
	--account $(ACCOUNT_NAME) \
	--rpc-url $(RPC_URL) \
	--broadcast \
	--etherscan-api-key $(ETHERSCAN_KEY) \
	--verify
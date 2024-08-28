

account :; cast wallet import $(ACCOUNT_NAME) --interactive

local-factory :; forge script script/Deploy.s.sol:DeployVaultFactory \
	--private-key $(PRIVATE_KEY) \
	--rpc-url $(RPC_URL) \
	--broadcast

deploy-factory :; forge script script/Deploy.s.sol:DeployVaultFactory \
	--account $(ACCOUNT_NAME) \
	--rpc-url $(RPC_URL) \
	--etherscan-api-key $(ETHERSCAN_KEY) \
	--verify \
	--broadcast
	


	
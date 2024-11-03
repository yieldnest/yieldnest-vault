

account :; cast wallet import $(ACCOUNT_NAME) --interactive

local-factory :; forge script script/DeployFactory.s.sol:DeployFactory \
	--private-key $(PRIVATE_KEY) \
	--rpc-url http://localhost:8545 \
	--broadcast

factory :; forge script script/DeployFactory.s.sol:DeployFactory \
	--account ${ACCOUNT_NAME} \
	--rpc-url ${RPC_URL} \
	--verify \
	--broadcast
	
vault :;
	cast send ${FACTORY_ADDRESS} \
		"createSingleVault(address,string,string,address,uint256,address[],address[])" \
		${ASSET_ADDRESS} "${VAULT_NAME}" "${VAULT_SYMBOL}" ${ADMIN_ADDRESS} ${MIN_DELAY} "[${PROPOSER_1},${PROPOSER_2}]" "[${EXECUTOR_1},${EXECUTOR_2}]" \
		--account ${ACCOUNT_NAME} \
		--rpc-url ${RPC_URL}


unit-test :; FOUNDRY_PROFILE=default forge test
holesky-test :; FOUNDRY_PROFILE=holesky forge test
mainnet-test :; FOUNDRY_PROFILE=mainnet forge test


account :; cast wallet import $(ACCOUNT_NAME) --interactive

local-factory :; forge script script/Deploy.s.sol:DeployVaultFactory \
	--private-key $(PRIVATE_KEY) \
	--broadcast

deploy-factory :; forge script script/Deploy.s.sol:DeployVaultFactory \
	--account ${ACCOUNT_NAME} \
	--rpc-url ${RPC_URL} \
	--verify \
	--broadcast
	
single-vault :;
	cast send ${FACTORY_ADDRESS} \
		"createSingleVault(address,string,string,address,uint256,address[],address[])" \
		${ASSET_ADDRESS} "${VAULT_NAME}" "${VAULT_SYMBOL}" ${ADMIN_ADDRESS} ${MIN_DELAY} "[${PROPOSER_1},${PROPOSER_2}]" "[${EXECUTOR_1},${EXECUTOR_2}]" \
		--account ${ACCOUNT_NAME} \
		--rpc-url ${RPC_URL}

echo "ERC20:"
# keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))

echo "vault:"
cast keccak "yieldnest.storage.vault"

echo "asset:"
cast keccak "yieldnest.storage.asset"

echo "strat:"
cast keccak "yieldnest.storage.strat"

echo "proc:"
cast keccak "yieldnest.storage.proc"

echo "fees:"
cast keccak "yieldnest.storage.fees"

echo "PROCESSOR_ROLE:"
cast keccak "PROCESSOR_ROLE"

echo "ALLOCATOR_ROLE:"
cast keccak "ALLOCATOR_ROLE"
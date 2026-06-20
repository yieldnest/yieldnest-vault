# AGENTS.md

This file tells Codex and other agents how to operate in `yieldnest-vault`.
It is also a deployment/configuration guide for people, LLMs, and config validators
checking YieldNest vault instances or concrete strategy instances.

## Purpose

This repo contains the core YieldNest vault system:

- ERC4626-style vault logic in [`src/Vault.sol`](src/Vault.sol) and [`src/BaseVault.sol`](src/BaseVault.sol)
- strategy base logic in [`src/strategy/BaseStrategy.sol`](src/strategy/BaseStrategy.sol)
- provider, guard, fee, and withdrawal modules under [`src/module/`](src/module) and [`src/withdraws/`](src/withdraws)
- deployment, verification, and role scripts under [`script/`](script)
- unit and mainnet-fork tests under [`test/`](test)

The default posture is conservative. Preserve accounting behavior, role boundaries, storage layout,
initializer behavior, and upgrade safety.

## Repo Map

- `src/`
  - `Vault.sol`, `BaseVault.sol`: core vault logic, accounting, roles, processor, hooks, fees
  - `strategy/BaseStrategy.sol`: abstract strategy base extending `BaseVault`
  - `withdraws/`: concrete withdrawer strategy logic and async withdrawal accounting
  - `module/`: provider, fee, guard, and related modules
  - `library/`: storage and accounting libraries
  - `interface/`, `utils/`, `hooks/`: support contracts
- `script/`
  - `general/`: simple implementation deploy scripts
  - `config/`: configuration flows such as `WithdrawerConfig`
  - `roles/`: role assignment helpers
  - `rules/`: processor rule builders
  - `verification/`: role, proxy, and configuration verification helpers
  - `upgrades/`: upgrade transaction data helpers
- `test/unit/`
  - isolated unit tests for vault and strategy behavior
- `test/mainnet/`
  - mainnet-fork integration tests for deployed-like flows
- `deployments/`
  - deployment artifacts and config outputs
- `broadcast/`, `out/`, `cache/`
  - generated artifacts; do not hand-edit unless explicitly required

## Deployment Model

YieldNest vault deployments are upgradeable proxy deployments. Distinguish these surfaces:

1. Implementation contract
   - `script/general/DeployVault.s.sol` deploys a `Vault` implementation only.
   - `script/general/DeployProvider.s.sol` deploys a `Provider` implementation only.
   - An implementation deployment is not a configured vault instance.

2. Proxy instance
   - A live instance should be a `TransparentUpgradeableProxy` pointing at the implementation.
   - The proxy admin owner should be the intended admin/timelock owner.
   - Verify proxy admin and owner with `script/verification/RolesVerification.sol`.

3. Initializer
   - Implementations disable initializers in constructors.
   - Initialize the proxy exactly once.
   - Do not call initializers on implementations.
   - Do not add new initializer paths without preserving upgrade safety.

## Inheritance Requirements

### Vault Instance

Use `src/Vault.sol` for a normal YieldNest vault instance. `Vault` is concrete and inherits:

```text
Vault -> BaseVault -> ERC20PermitUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable
Vault -> LinearWithdrawalFee
```

A vault instance must be initialized through `Vault.initialize(...)` on the proxy.

### Base Strategy Instance

`src/strategy/BaseStrategy.sol` is abstract. It is not deployable by itself.

To deploy a strategy-like instance, deploy a concrete contract that inherits `BaseStrategy` and implements or composes
the missing behavior required by the intended strategy. Examples in this repo:

- `src/withdraws/BaseWithdrawer.sol` inherits `BaseStrategy` and supplies an initializer and zero-fee behavior.
- `src/withdraws/Withdrawer.sol` inherits `BaseWithdrawer` and implements async withdrawal accounting.
- `test/unit/mocks/MockStrategy.sol` is a test-only example of a concrete `BaseStrategy` plus `LinearWithdrawalFee`.

A config validator must reject any plan that says "deploy BaseStrategy" directly. The plan must name the concrete
strategy contract, its inheritance chain, initializer, fee behavior, and any overridden accounting/withdrawal logic.

## Vault Instance Configuration

A normal `Vault` proxy is initialized with:

```solidity
Vault.initialize(
    address admin,
    string memory name,
    string memory symbol,
    uint8 decimals_,
    uint64 baseWithdrawalFee_,
    bool countNativeAsset_,
    bool alwaysComputeTotalAssets_,
    uint256 defaultAssetIndex_
)
```

Parameter meanings and validation:

- `admin`
  - Receives `DEFAULT_ADMIN_ROLE` during initialization.
  - Deployment policy: must not be `address(0)`, even though current tests document that the initializer itself does
    not revert on zero admin.
  - In production flows this can be a temporary deployer if the script immediately grants final roles and renounces
    temporary roles. Final validation must prove temporary deployer admin was removed.

- `name`
  - ERC20 share token name.
  - Must match the intended vault product name and deployment artifacts.

- `symbol`
  - ERC20 share token symbol.
  - Must match deployment artifacts, UI/indexer expectations, and verification scripts.

- `decimals_`
  - ERC20 share token decimals and base-asset accounting decimals.
  - Must be nonzero.
  - The first added asset, the base asset at asset index `0`, must have exactly these decimals.
  - If `countNativeAsset_ == true`, the base asset decimals must be `18`.

- `baseWithdrawalFee_`
  - Initial withdrawal fee used by `LinearWithdrawalFee`.
  - Scale is `FeeMath.BASIS_POINT_SCALE = 1e8`, where `1e8 == 100%`.
  - `1e6 == 1%`, `1e5 == 0.1%`, and `0 == no base withdrawal fee`.
  - Must not exceed the fee scale enforced by the fee library.
  - The configured value should be approved by the deployment spec; fee changes require `FEE_MANAGER_ROLE`.

- `countNativeAsset_`
  - If `true`, `computeTotalAssets()` includes `address(this).balance` as base-denominated assets.
  - Use `true` only when native ETH is intentionally part of accounting and the base denomination is 18 decimals.
  - Use `false` for ERC20-only vaults.

- `alwaysComputeTotalAssets_`
  - If `true`, `totalBaseAssets()` computes balances and provider rates live on each read.
  - If `false`, `totalBaseAssets()` returns cached storage updated by deposits, withdrawals, and `processAccounting()`.
  - `false` is cheaper but requires a valid accounting process. If toggled from `true` to `false`, the contract calls
    `_processAccounting()` immediately.

- `defaultAssetIndex_`
  - Selects `asset()` for ERC4626 default operations.
  - Must be `0` or `1`; higher indexes revert.
  - Index `0` means the base asset is also the ERC4626 default asset.
  - Index `1` means the default asset is the second asset added.
  - The base asset and default asset must not be deleted. The default asset must be the underlying asset of the base
    asset when they differ, per `BaseVault` requirements.

After initialization, a vault must be configured in this order unless the deployment script proves an equivalent safe
ordering:

1. Grant final roles and temporary deployer roles.
2. Set the provider with `setProvider(provider)`.
3. Add assets with `addAsset(asset, active)`.
4. Set the buffer with `setBuffer(buffer)` if ERC4626 `withdraw`/`redeem` should be enabled.
5. Set processor rules with `setProcessorRule` or `setProcessorRules`.
6. Set hooks with `setHooks(hooks)` only if hooks are intended and `IHooks(hooks).VAULT() == vault`.
7. Configure withdrawal fees and fee overrides if applicable.
8. Call `processAccounting()` when cached accounting is used and the initial state needs synchronization.
9. Unpause only after provider, assets, buffer/rules/hooks, roles, and accounting are verified.
10. Renounce all temporary deployer roles.

## Base Strategy Configuration

Because `BaseStrategy` is abstract, a strategy instance must be configured through the concrete child contract's
initializer. A validator must read that concrete initializer and map each argument back to `BaseVault._initialize(...)`
and any strategy-specific storage.

Common inherited configuration:

- `admin`, `name`, `symbol`, `decimals_`, `countNativeAsset_`, `alwaysComputeTotalAssets_`, `defaultAssetIndex_`
  have the same meaning as for `Vault`, except the child contract may hardcode some values.
- `paused_` is passed internally to `_initialize`. Production strategy instances should normally start paused until
  provider, assets, roles, and processor permissions are configured.
- Fee behavior is not defined by `BaseStrategy`. The concrete child must implement `_feeOnRaw` and `_feeOnTotal`,
  either by composing a fee module such as `LinearWithdrawalFee` or by returning zero fees.

Strategy-specific configuration:

- `hasAllocators`
  - Stored in `BaseStrategyStorage`.
  - If `true`, deposits and withdrawals require `ALLOCATOR_ROLE` through `onlyAllocator`.
  - If `false`, allocator gating is disabled and any normal ERC4626 caller can use allowed deposit/withdraw flows.
  - Managed by `ALLOCATOR_MANAGER_ROLE` through `setHasAllocator`.
  - `BaseWithdrawer.initialize(...)` always sets this to `true`.

- `isAssetWithdrawable[asset]`
  - Controls whether an asset can be withdrawn/redeemed from the strategy.
  - Managed by `ASSET_MANAGER_ROLE` through `setAssetWithdrawable`.
  - Strategy `addAsset(asset, depositable, withdrawable)` sets both deposit active status and withdrawable status.
  - Deleting an asset clears its withdrawable flag.

- `available assets`
  - `BaseStrategy._availableAssets(asset)` defaults to the token balance held by the strategy.
  - Concrete strategies can override this for protocol-specific liquidity.
  - Validators must understand this override before approving withdrawability.

- `computeTotalAssets()`
  - Inherited default counts native asset, ERC20 balances, and provider rates.
  - Concrete strategies can override this for queued, staked, or async positions.
  - `BaseWithdrawer.computeTotalAssets()` adds `asyncWithdrawalBalance(asset)` for each listed asset.

Concrete strategy configuration sequence:

1. Deploy the concrete implementation, not `BaseStrategy`.
2. Deploy a proxy for the concrete implementation.
3. Call the concrete initializer on the proxy exactly once.
4. Grant final roles, including `ALLOCATOR_MANAGER_ROLE` and any needed `ALLOCATOR_ROLE`.
5. Set provider.
6. Add assets using the concrete strategy's asset function. For `BaseStrategy`, prefer
   `addAsset(asset, decimals, depositable, withdrawable)` when decimals must be explicit.
7. Set withdrawability deliberately for each asset.
8. Set processor rules for every external protocol action the strategy may execute.
9. Configure hooks and fees only if the concrete child supports them.
10. Unpause only after role, asset, provider, processor, accounting, and allocator checks pass.
11. Renounce temporary deployer roles.

## Asset Configuration Rules

Asset list order is security-critical:

- Asset index `0` is the base asset.
- Asset index `defaultAssetIndex()` is the ERC4626 default asset returned by `asset()`.
- `defaultAssetIndex` must be `0` or `1`.
- The base asset and default asset cannot be deleted.
- The first asset's decimals must equal `decimals_`.
- If native ETH is counted, the first asset must have 18 decimals.
- Non-base assets cannot have more decimals than the base asset.
- The base asset cannot be added twice.
- Duplicate non-base assets are rejected.
- An asset must have zero token balance before deletion.
- `active == true` means depositable for vault deposits.
- For strategies, `withdrawable == true` separately controls withdrawal/redemption availability.

A config validator should verify:

- `getAssets()` returns the expected assets in the expected order.
- `asset()` equals `getAssets()[defaultAssetIndex()]`.
- `getAsset(asset).active` matches deposit policy.
- For strategies, `getAssetWithdrawable(asset)` matches withdrawal policy.
- Provider supports every configured asset and returns rates in the expected base denomination.

## Provider Configuration

The provider is the rate source used by conversions and accounting:

- Set with `setProvider(provider)`; requires `PROVIDER_MANAGER_ROLE`.
- Provider cannot be `address(0)`.
- `unpause()` reverts if provider is unset.
- `Provider.getRate(asset)` must support every configured asset.
- Rate precision is interpreted with the asset's decimals:
  - base assets are computed as `assets * rate / 10 ** assetDecimals`
  - asset amounts are computed as `baseAssets * 10 ** assetDecimals / rate`

Provider misconfiguration directly breaks deposits, withdrawals, share pricing, and accounting. A validator must call
`getRate(asset)` for every configured asset and compare the result to the intended oracle/pricing model.

## Buffer Configuration

The buffer is the strategy/source used by `BaseVault` withdrawals:

- Set with `setBuffer(buffer)`; requires `BUFFER_MANAGER_ROLE`.
- `buffer == address(0)` is allowed, but disables normal ERC4626 `withdraw`/`redeem` paths that require buffer assets.
- Strategy withdrawals override parts of this behavior; do not assume a strategy uses buffer the same way as `Vault`.

For normal vaults, a validator should check that the buffer is set before unpause if user withdrawals are intended.

## Processor Rule Configuration

`processor(targets, values, data)` can execute arbitrary calls only when each call is allowed by `Guard`:

- Caller must have `PROCESSOR_ROLE`.
- Each `(target, function selector)` must have an active `FunctionRule`.
- `FunctionRule.isActive == true` enables the function selector for that target.
- `FunctionRule.paramRules` can restrict address parameters by allowlist.
- `FunctionRule.validator` can perform custom validation; if nonzero, it is used instead of generic param-rule checks.
- Rules are set by `PROCESSOR_MANAGER_ROLE`.

A validator must reject configurations with broad processor permissions that are not justified by the deployment spec.
For every processor rule, record:

- target contract
- function selector/signature
- whether ETH value is expected
- allowed address parameters
- validator contract, if any
- operational reason for the permission

## Hooks Configuration

Hooks are optional and can intercept deposit, withdraw, redeem, and accounting flows:

- Set with `setHooks(hooks)`; requires `HOOKS_MANAGER_ROLE`.
- `hooks == address(0)` disables hooks.
- Nonzero hooks must return this vault from `IHooks(hooks).VAULT()`.
- Only the hooks contract can call `mintShares`.

Hooks can change accounting and share supply behavior. A validator must treat nonzero hooks as a high-risk extension and
review the hook contract and configuration before unpause.

## Roles

Core `BaseVault` roles:

- `DEFAULT_ADMIN_ROLE`
  - Can grant and revoke roles.
  - Final holder should be the intended admin/security council or governance authority.
  - Temporary deployer admin must be removed after configuration.

- `PROCESSOR_ROLE`
  - Can call `processor(...)` and any concrete functions protected by `PROCESSOR_ROLE`.
  - High-risk operational role. It can move funds according to active processor rules.

- `PAUSER_ROLE`
  - Can pause the vault.
  - Should be available to an emergency multisig/operator.

- `UNPAUSER_ROLE`
  - Can unpause the vault.
  - Should be more tightly controlled than `PAUSER_ROLE`.
  - Unpause requires provider to be set.

- `PROVIDER_MANAGER_ROLE`
  - Can change the provider.
  - High-risk because provider rates control share pricing and accounting.
  - Typically timelocked.

- `BUFFER_MANAGER_ROLE`
  - Can change the buffer.
  - High-risk because buffer affects withdrawals.
  - Typically timelocked.

- `ASSET_MANAGER_ROLE`
  - Can add, update, and delete assets.
  - Can toggle cached/live accounting via `setAlwaysComputeTotalAssets`.
  - In strategies, can set asset withdrawability.
  - High-risk because asset order, active status, decimals, and withdrawability affect ERC4626 behavior.

- `PROCESSOR_MANAGER_ROLE`
  - Can set processor rules.
  - High-risk because processor rules define the external call surface.
  - Typically timelocked.

- `HOOKS_MANAGER_ROLE`
  - Can set hooks.
  - High-risk because hooks can intercept flows and hooks alone can mint shares through `mintShares`.

- `ASSET_WITHDRAWER_ROLE`
  - In `BaseVault`, can call the permissioned asset withdrawal path.
  - `BaseStrategy` overrides `withdrawAsset`, so do not assume this role works the same on strategy instances.

`Vault` role:

- `FEE_MANAGER_ROLE`
  - Can call `setBaseWithdrawalFee` and `overrideBaseWithdrawalFee`.
  - Controls withdrawal fee policy.

`BaseStrategy` roles:

- `ALLOCATOR_ROLE`
  - Required for deposits and withdrawals when `hasAllocators == true`.
  - Operational role for permissioned strategy allocation.

- `ALLOCATOR_MANAGER_ROLE`
  - Can toggle allocator gating with `setHasAllocator`.
  - High-risk because setting `hasAllocators` to `false` opens strategy deposit/withdraw paths to normal ERC4626 callers.

Script helper expectations:

- `BaseRoles.configureDefaultRoles` grants:
  - `DEFAULT_ADMIN_ROLE` to `actors.ADMIN()`
  - `PROCESSOR_ROLE` to `actors.PROCESSOR()`
  - `PAUSER_ROLE` to `actors.PAUSER()`
  - `UNPAUSER_ROLE` to `actors.UNPAUSER()`
  - `PROVIDER_MANAGER_ROLE`, `ASSET_MANAGER_ROLE`, `BUFFER_MANAGER_ROLE`, and `PROCESSOR_MANAGER_ROLE` to timelock
- `BaseRoles.configureTemporaryRoles` grants deployer temporary setup roles.
- `BaseRoles.renounceTemporaryRoles` must be called before finalization.
- Verification should prove deployer no longer has temporary roles.

## Final Configuration Checklist

Before considering a vault or strategy instance correctly configured:

1. The proxy points to the intended implementation.
2. Proxy admin and proxy admin owner are correct.
3. The implementation contract itself is not initialized.
4. The proxy initializer was called once with expected arguments.
5. The contract starts paused and is only unpaused after full configuration.
6. Provider is nonzero and supports all configured assets.
7. Asset order, decimals, active flags, and default asset are correct.
8. Strategy withdrawability and allocator gating are correct, if applicable.
9. Buffer is correct, or intentionally zero with documented withdrawal impact.
10. Processor rules are minimal, active only where intended, and validated.
11. Hooks are zero or reviewed and bound to the correct vault.
12. Fees and fee overrides match the deployment spec.
13. Accounting mode is correct and `processAccounting()` has been run when needed.
14. Final roles match the intended actors/timelock.
15. Temporary deployer roles have been renounced.
16. Mainnet or fork verification scripts pass for the touched deployment.

## Working Rules

1. Make the smallest defensible change.
2. Do not silently change public interfaces, role semantics, or storage layout.
3. Do not modify deployment artifacts, broadcast outputs, or generated files unless the task explicitly calls for it.
4. When touching accounting, ERC4626 behavior, fees, slashing, provider routing, or withdrawals, prefer additional tests
   over explanation-only changes.
5. When working on upgradeability-sensitive code, treat storage layout and initializer behavior as first-class constraints.
6. If a change affects security assumptions, state the risk clearly in the final summary.

## Source Of Truth

When inferring intent, prefer this order:

1. tests covering the touched behavior
2. concrete implementation in `src/`
3. deployment and verification scripts in `script/`
4. repo docs in `docs/`
5. audit notes and ad hoc markdown only as supporting context

If docs and tests disagree, trust tests and implementation, then call out the inconsistency.

## Commands

Run commands from the repo root.

### Install / setup

```bash
forge install
```

### Format

```bash
make fmt
```

### Lint

```bash
make lint
```

### Unit tests

```bash
make unit
```

Equivalent:

```bash
FOUNDRY_PROFILE=default forge test
```

### Mainnet-fork tests

Requires `ETH_MAINNET_RPC_URL`.

```bash
make main
```

Equivalent:

```bash
FOUNDRY_PROFILE=mainnet forge test
```

### Coverage

```bash
make cover
```

## Validation Expectations

Use the narrowest validation that actually covers the change, then widen if needed.

### If you touch only documentation

No Solidity tests are required unless the documentation change reveals a code/config mismatch that must be fixed.

### If you touch only a small unit-scoped contract or function

Run targeted tests first, for example:

```bash
FOUNDRY_PROFILE=default forge test --match-path test/unit/vault/accounting.t.sol
```

or

```bash
FOUNDRY_PROFILE=default forge test --match-contract <ContractName>
```

### If you touch vault accounting, ERC4626 flows, fees, hooks, slashing, or withdrawals

Run at minimum:

```bash
FOUNDRY_PROFILE=default forge test --match-path test/unit/vault/*
```

Narrower targeted commands are acceptable during iteration, but before finalizing run the relevant suite.

### If you touch strategy logic

Run at minimum the relevant strategy suite, for example:

```bash
FOUNDRY_PROFILE=default forge test --match-path test/unit/strategy/*
```

### If you touch deployment scripts, provider integrations, processor flows, withdrawers, or upgrades

Run the relevant mainnet-fork tests if possible, for example:

```bash
FOUNDRY_PROFILE=mainnet forge test --match-path test/mainnet/provider.spec.sol
FOUNDRY_PROFILE=mainnet forge test --match-path test/mainnet/processor.spec.sol
FOUNDRY_PROFILE=mainnet forge test --match-path test/mainnet/upgrade.spec.sol
FOUNDRY_PROFILE=mainnet forge test --match-path test/mainnet/withdrawer.spec.sol
```

If RPC access is missing or flaky, say so explicitly.

## Solidity-Specific Guidance

### Vault and ERC4626 work

- Preserve share/accounting invariants.
- Be explicit about asset decimals vs share decimals.
- Be careful with `convertToAssets`, `convertToShares`, previews, and fee interactions.
- If changing redeem/withdraw behavior, check both unit and fork tests.

### Upgradeable patterns

- Do not reorder or remove storage variables in upgradeable contracts.
- Be careful with initializer flows and access control setup.
- If a change is upgrade-sensitive, mention storage/initializer considerations in the final response.

### Fees and slashing

- Treat fee math and slashing math as precision-sensitive.
- Preserve existing rounding conventions unless the task explicitly requires a change.
- Add or update tests that demonstrate the intended before/after behavior.

### Providers / external integrations

- Do not assume external protocol behavior; rely on existing abstractions and tests.
- Keep external-call changes narrow.
- If a provider change modifies how assets are priced, allocated, or withdrawn, say so explicitly.

## Scripts And Deployments

- Prefer existing scripts in `script/` over inventing new one-off approaches.
- When updating a deploy or verification script, keep config and script changes aligned.
- Do not rewrite `broadcast/` outputs by hand.
- Do not commit environment-specific secrets or RPC values.

## Testing Strategy

When adding tests:

- place unit tests next to the closest existing suite
- extend the existing helper/setup pattern instead of creating parallel abstractions
- prefer explicit scenario coverage for edge cases
- add invariant-style coverage when changing accounting or withdrawal semantics

Useful existing areas:

- `test/unit/vault/`
- `test/unit/strategy/`
- `test/mainnet/`
- `test/utils/`

## Review Checklist

Before finalizing, check:

- Does the change preserve role boundaries?
- Does it preserve storage layout and initializer safety where applicable?
- Does it preserve ERC4626/accounting semantics?
- Are decimals and rounding handled correctly?
- Are the relevant tests run?
- Are generated artifacts left untouched unless explicitly requested?

## Final Response Expectations

In the final response:

- summarize what changed
- state what you validated
- mention any tests not run
- call out real risks, assumptions, or follow-up items

Keep it concise and technical.

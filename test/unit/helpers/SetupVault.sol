// SPDX-License-Identifier: BSD Clause-3
pragma solidity ^0.8.24;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";
import {IValidator} from "src/interface/IValidator.sol";
import {MockProvider} from "test/unit/mocks/MockProvider.sol";
import {PublicViewsVault} from "test/unit/helpers/PublicViewsVault.sol";
import {MockSwapper} from "test/unit/mocks/MockSwapper.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FeeHooks} from "src/module/FeeHooks.sol";
import {IHooks} from "src/interface/IHooks.sol";

contract SetupVault is Test, Etches, MainnetActors {
    function setup() public virtual returns (Vault vault, WETH9 weth) {
        string memory name = "YieldNest MAX";
        string memory symbol = "ynMAx";

        Vault vaultImplementation = new PublicViewsVault();

        // Deploy the proxy
        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, "");

        vault = Vault(payable(address(vaultProxy)));

        // Initialize the vault
        vault.initialize(ADMIN, name, symbol, 18, 0, true, false, 0);

        IHooks.Config memory config = IHooks.Config({
            beforeDeposit: false,
            afterDeposit: false,
            beforeMint: false,
            afterMint: false,
            beforeRedeem: false,
            afterRedeem: true,
            beforeWithdraw: true,
            afterWithdraw: false,
            beforeProcessAccounting: false,
            afterProcessAccounting: true
        });

        FeeHooks hooks = new FeeHooks(address(vaultProxy), ADMIN, 1e17, FEE_MANAGER, config);

        weth = WETH9(payable(MC.WETH));

        if (block.chainid == 31337) {
            configureLocal(vault, hooks);
        }

        if (block.chainid == 1) {
            configureMainnet(vault);
        }
    }

    function configureLocal(Vault vault, FeeHooks hooks) internal virtual {
        // etch to mock the mainnet contracts
        mockAll();

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);
        vault.grantRole(vault.FEE_MANAGER_ROLE(), FEE_MANAGER);
        vault.grantRole(vault.HOOKS_MANAGER_ROLE(), HOOKS_MANAGER);

        // test cannot unpause vault withtout buffer
        vm.expectRevert();
        vault.unpause();

        // set the rate provider contract
        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true);
        vault.addAsset(MC.BUFFER, false);
        vault.addAsset(MC.STETH, true);
        vault.addAsset(MC.WBTC, true);
        vault.addAsset(MC.METH, true);

        // configure processor rules
        setDepositRule(vault, MC.BUFFER, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER);
        setApprovalRule(vault, MC.WETH, MC.BUFFER);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        // add strategies

        vault.setBuffer(MC.BUFFER);

        // Set WBTC rate to 20 ETH
        MockProvider(MC.PROVIDER).setRate(MC.WBTC, 20e18);
        // Set METH rate to 1.2 ETH
        MockProvider(MC.PROVIDER).setRate(MC.METH, 1.2e18);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();

        vm.startPrank(HOOKS_MANAGER);
        vault.setHooks(address(hooks));
        vm.stopPrank();
    }

    function configureMainnet(Vault vault) internal {
        // etch to mock the mainnet contracts

        mockAll();

        string memory name = "YieldNest ETH MAX";
        string memory symbol = "ynETHx";

        Vault vaultImplementation = new Vault();

        // Deploy the proxy
        bytes memory initData = abi.encodeWithSelector(Vault.initialize.selector, ADMIN, name, symbol, 18);

        TUProxy vaultProxy = new TUProxy(address(vaultImplementation), ADMIN, initData);

        // Create a Vault interface pointing to the proxy
        vault = Vault(payable(address(vaultProxy)));

        vm.startPrank(ADMIN);

        vault.grantRole(vault.PROCESSOR_ROLE(), PROCESSOR);
        vault.grantRole(vault.PROVIDER_MANAGER_ROLE(), PROVIDER_MANAGER);
        vault.grantRole(vault.BUFFER_MANAGER_ROLE(), BUFFER_MANAGER);
        vault.grantRole(vault.ASSET_MANAGER_ROLE(), ASSET_MANAGER);
        vault.grantRole(vault.PROCESSOR_MANAGER_ROLE(), PROCESSOR_MANAGER);
        vault.grantRole(vault.PAUSER_ROLE(), PAUSER);
        vault.grantRole(vault.UNPAUSER_ROLE(), UNPAUSER);

        vault.setProvider(MC.PROVIDER);

        // Add assets: Base asset always first
        vault.addAsset(MC.WETH, true);
        vault.addAsset(MC.STETH, true);
        vault.addAsset(MC.YNETH, true);
        vault.addAsset(MC.YNLSDE, true);

        setDepositRule(vault, MC.BUFFER, address(vault));
        setDepositRule(vault, MC.YNETH, address(vault));
        setDepositRule(vault, MC.YNLSDE, address(vault));
        setWethDepositRule(vault, MC.WETH);

        setApprovalRule(vault, address(vault), MC.BUFFER);
        setApprovalRule(vault, MC.WETH, MC.BUFFER);
        setApprovalRule(vault, address(vault), MC.YNETH);
        setApprovalRule(vault, address(vault), MC.YNLSDE);

        vault.setBuffer(MC.BUFFER);

        // Unpause the vault
        vault.unpause();
        vm.stopPrank();
    }

    function setDepositRule(Vault vault_, address contractAddress, address receiver) internal {
        bytes4 funcSig = bytes4(keccak256("deposit(uint256,address)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        address[] memory allowList = new address[](1);
        allowList[0] = receiver;

        paramRules[1] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setApprovalRule(Vault vault_, address contractAddress, address spender) internal {
        bytes4 funcSig = bytes4(keccak256("approve(address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](2);

        address[] memory allowList = new address[](1);
        allowList[0] = spender;

        paramRules[0] = IVault.ParamRule({paramType: IVault.ParamType.ADDRESS, isArray: false, allowList: allowList});

        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});
        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(contractAddress, funcSig, rule);
    }

    function setWethDepositRule(Vault vault_, address weth_) public {
        bytes4 funcSig = bytes4(keccak256("deposit()"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](0);

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(weth_, funcSig, rule);
    }

    function setupSwapper(Vault vault_, address[] memory swapableAssets) internal returns (MockSwapper swapper) {
        // Deploy mock swapper
        swapper = new MockSwapper(vault_.provider());

        // Set up approval rules for all swapable assets
        for (uint256 i = 0; i < swapableAssets.length; i++) {
            setApprovalRule(vault_, swapableAssets[i], address(swapper));
        }

        // Set up swap function rule
        bytes4 funcSig = bytes4(keccak256("swap(address,address,uint256)"));

        IVault.ParamRule[] memory paramRules = new IVault.ParamRule[](3);

        // First param: fromToken (address) - allow any token
        paramRules[0] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Second param: toToken (address) - allow any token
        paramRules[1] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        // Third param: amountIn (uint256) - allow any amount
        paramRules[2] =
            IVault.ParamRule({paramType: IVault.ParamType.UINT256, isArray: false, allowList: new address[](0)});

        IVault.FunctionRule memory rule =
            IVault.FunctionRule({isActive: true, paramRules: paramRules, validator: IValidator(address(0))});

        vault_.setProcessorRule(address(swapper), funcSig, rule);

        // Transfer 10 billion of each asset to the Swapper with appropriate decimals
        for (uint256 i = 0; i < swapableAssets.length; i++) {
            address asset = swapableAssets[i];
            uint256 decimals = IERC20Metadata(asset).decimals();
            uint256 amount = 10_000_000_000 * (10 ** decimals);
            deal(asset, address(swapper), amount);
        }

        return swapper;
    }
}

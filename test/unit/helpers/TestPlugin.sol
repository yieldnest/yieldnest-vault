pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";
import {Vault} from "src/Vault.sol";
import {IVault} from "src/interface/IVault.sol";
import {TransparentUpgradeableProxy as TUProxy, IERC20} from "src/Common.sol";
import {WETH9} from "test/unit/mocks/MockWETH.sol";
import {Etches} from "test/unit/helpers/Etches.sol";
import {MainnetActors} from "script/Actors.sol";
import {MainnetContracts as MC} from "script/Contracts.sol";

contract TestPlugin {
    address private immutable TARGET_SINGLETON;

    error OnlyDelegateCallAllowed();
    error NotAllowed();

    constructor() {
        TARGET_SINGLETON = address(this);
    }

    modifier onlyDelegateCall() {
        if (msg.sender == TARGET_SINGLETON) {
            revert OnlyDelegateCallAllowed();
        }
        _;
    }

    struct DepositData {
        address vault;
        address recipient;
    }

    struct ApprovalData {
        address token;
        address spender;
    }

    struct WethDepositData {
        address target;
    }

    struct PluginData {
        DepositData[] deposits;
        ApprovalData[] approvals;
        WethDepositData[] wethDeposits;
    }

    mapping(address => mapping(address => bool)) public isDepositAllowed;

    mapping(address => mapping(address => bool)) public isApprovalAllowed;

    mapping(address => bool) public isWethDepositAllowed;

    bool internal _initialized;

    function init(bytes memory _pluginData) public onlyDelegateCall {
        if (_initialized) {
            revert();
        }

        PluginData memory data = abi.decode(_pluginData, (PluginData));

        for (uint256 i = 0; i < data.deposits.length; i++) {
            isDepositAllowed[data.deposits[i].vault][data.deposits[i].recipient] = true;
        }

        for (uint256 i = 0; i < data.approvals.length; i++) {
            isApprovalAllowed[data.approvals[i].token][data.approvals[i].spender] = true;
        }

        for (uint256 i = 0; i < data.wethDeposits.length; i++) {
            isWethDepositAllowed[data.wethDeposits[i].target] = true;
        }

        _initialized = true;
    }

    function depositIntoVault(address vault, uint256 amount, address recipient) public onlyDelegateCall {
        if (!isDepositAllowed[vault][recipient]) {
            revert NotAllowed();
        }
        IVault(vault).deposit(amount, recipient);
    }

    function depositWeth(address target, uint256 amount) public payable onlyDelegateCall {
        if (!isWethDepositAllowed[target]) {
            revert NotAllowed();
        }
        WETH9(payable(target)).deposit{value: amount}();
    }

    function approveToken(address token, address spender, uint256 amount) public onlyDelegateCall {
        if (!isApprovalAllowed[token][spender]) {
            revert NotAllowed();
        }
        IERC20(token).approve(spender, amount);
    }
}

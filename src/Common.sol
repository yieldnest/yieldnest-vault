// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.24;

import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Address} from "lib/openzeppelin-contracts/contracts/utils/Address.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ERC20PermitUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20Upgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ETHRateProvider} from "src/module/ETHRateProvider.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20Metadata.sol";
import {IERC20Permit} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IStakeManager} from "lib/synclub-contracts/contracts/interfaces/IStakeManager.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ProxyAdmin} from "lib/openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {TimelockController} from "lib/openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {TimelockControllerUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/governance/TimelockControllerUpgradeable.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol";


contract Common {}

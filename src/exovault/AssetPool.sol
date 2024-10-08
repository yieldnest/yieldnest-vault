// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import "./YnAsset.sol";
import "./IRateProvider.sol";


contract AssetPool is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;

    bytes32 public constant ASSET_ADMIN_ROLE = keccak256("ASSET_ADMIN_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct Asset {
        bool active;
    }

    YnAsset public ynAsset;
    IRateProvider public rateProvider;
    mapping(address => Asset) public assets;
    IERC20[] public assetList;
    IERC20[] public strategyList;
    address public exoVault;

    function initialize(YnAsset _ynAsset, IRateProvider _rateProvider, address _exoVault) public initializer {
        ynAsset = _ynAsset;
        rateProvider = _rateProvider;
        exoVault = _exoVault;
    }

    function addAsset(IERC20 asset) external onlyRole(ASSET_ADMIN_ROLE) {
        require(!assets[address(asset)].active, "Asset already added");
        assets[address(asset)] = Asset(true);
        assetList.push(asset);
    }

    function addStrategy(IERC20 strategy) external onlyRole(ASSET_ADMIN_ROLE) {
        require(!assets[address(strategy)].active, "Strategy already added");
        assets[address(strategy)] = Asset(true);
        strategyList.push(strategy);
    }


    function manage(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    )
    external
    onlyRole(MANAGER_ROLE)
    returns (bytes[] memory results)
    {
        uint256 targetsLength = targets.length;
        results = new bytes[](targetsLength);
        for (uint256 i; i < targetsLength; ++i) {
            results[i] = targets[i].functionCallWithValue(data[i], values[i]);
        }
    }

    function deposit(address asset, uint256 _amount, address _receiver) external {
        require(assets[asset].active, "Asset not supported");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);
        
        uint256 ynAssetAmount = rateProvider.convert(asset, _amount);
        ynAsset.mint(_receiver, ynAssetAmount);
    }

    function mintRewards() external onlyRole(ASSET_ADMIN_ROLE) {
        uint256 amountToMint = 0; // todo: how to calculate 
        ynAsset.mint(exoVault, amountToMint);
    }

    // TODO: add async redemption logic or YnAsset
}

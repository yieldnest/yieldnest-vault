// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./YnAsset.sol";
import "./IRateProvider.sol";


contract AssetPool is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant ASSET_ADMIN_ROLE = keccak256("ASSET_ADMIN_ROLE");

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

    function deposit(address asset, uint256 _amount, address _receiver) external {
        require(assets[asset].active, "Asset not supported");
        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);
        
        uint256 ynAssetAmount = rateProvider.convert(asset, _amount);
        ynAsset.mint(_receiver, ynAssetAmount);
    }

    function mintRewards() external onlyRole(ASSET_ADMIN_ROLE) {
        uint256 totalValue = 0;

        // Calculate total value of assets
        for (uint256 i = 0; i < assetList.length; i++) {
            IERC20 asset = assetList[i];
            uint256 balance = asset.balanceOf(address(this));
            totalValue += rateProvider.convert(address(asset), balance);
        }

        // Calculate total value of strategies
        for (uint256 i = 0; i < strategyList.length; i++) {
            IERC20 strategy = strategyList[i];
            uint256 balance = strategy.balanceOf(address(this));
            totalValue += rateProvider.convert(address(strategy), balance);
        }

        // Calculate the amount of ynAsset to mint
        uint256 currentSupply = ynAsset.totalSupply();
        if (totalValue > currentSupply) {
            uint256 amountToMint = totalValue - currentSupply;
            ynAsset.mint(exoVault, amountToMint);
        }
    }

    // TODO: add async redemption logic or YnAsset
}

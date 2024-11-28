
interface ISlisBnbStakeManager {
    function convertSnBnbToBnb(uint256 amount) external view returns (uint256);
    function convertBnbToSnBnb(uint256 amount) external view returns (uint256);

    function deposit() external payable returns (uint256);
}

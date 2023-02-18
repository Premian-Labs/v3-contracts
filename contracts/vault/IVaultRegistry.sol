// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IVaultRegistry {
    enum TradeSide {Buy, Sell, Both}
    enum OptionType {Call, Put, Both}

    function vaults() external view returns (address[] memory);
    function vaultsPerTradeSide(TradeSide side) external view returns (address[] memory);
    function vaultsPerOptionType(OptionType optionType) external view returns (address[] memory);
    function vaultsLength() external view returns (uint256);
    function vaultsPerTradeSideLength(TradeSide side) external view returns (uint256);
    function vaultsPerOptionTypeLength(OptionType optionType) external view returns (uint256);
    function vault(uint256 index) external view returns (address);
    function getVaults(TradeSide side, OptionType optionType) external view returns (address[] memory);
    function getVaults(TradeSide[] memory sides, OptionType[] memory optionTypes) external view returns (address[] memory);

    function addVault(address _vault, TradeSide side, OptionType optionType) external;
    function removeVault(uint256 index) external;
    function removeVault(address _vault) external;
}

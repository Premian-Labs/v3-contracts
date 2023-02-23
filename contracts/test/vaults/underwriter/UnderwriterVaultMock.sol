// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UnderwriterVault, SolidStateERC4626} from "../../../vaults/underwriter/UnderwriterVault.sol";
import {UnderwriterVaultStorage} from "../../../vaults/underwriter/UnderwriterVaultStorage.sol";
import "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import "hardhat/console.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

contract UnderwriterVaultMock is UnderwriterVault {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSet for EnumerableSet.UintSet;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;

    constructor(
        address oracleAddress,
        address factoryAddress
    ) UnderwriterVault(oracleAddress, factoryAddress) {}

    function getTotalFairValue() external view returns (uint256) {
        return _getTotalFairValue();
    }

    function getTotalLockedSpread() external view returns (uint256) {
        return _getTotalLockedSpread();
    }

    function increasePositionSize(
        uint256 maturity,
        uint256 strike,
        uint256 positionSize
    ) external onlyOwner {
        UnderwriterVaultStorage.layout().positionSizes[maturity][
            strike
        ] += positionSize;
    }

    function setLastSpreadUnlockUpdate(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().lastSpreadUnlockUpdate = value;
    }

    function setMinMaturity(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().minMaturity = value;
    }

    function setMaxMaturity(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().maxMaturity = value;
    }

    function insertMaturity(
        uint256 maturity,
        uint256 newMaturity
    ) external onlyOwner {
        UnderwriterVaultStorage.layout().maturities.insertAfter(
            maturity,
            newMaturity
        );
    }

    function insertStrike(uint256 maturity, uint256 strike) external onlyOwner {
        UnderwriterVaultStorage.layout().maturityToStrikes[maturity].add(
            strike
        );
    }

    function increaseSpreadUnlockingRate(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().spreadUnlockingRate += value;
    }

    function increaseSpreadUnlockingTick(
        uint256 maturity,
        uint256 value
    ) external onlyOwner {
        UnderwriterVaultStorage.layout().spreadUnlockingTicks[
            maturity
        ] += value;
    }

    function increaseTotalLockedAssets(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().totalLockedAssets += value;
    }

    function increaseTotalLockedSpread(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().totalLockedSpread += value;
    }

    function increaseTotalAssets(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().totalAssets += value;
    }

    function lastMaturity() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().lastMaturity;
    }

    function nextMaturity() external view returns (uint256) {
        uint256 last = UnderwriterVaultStorage.layout().lastMaturity;

        return UnderwriterVaultStorage.layout().maturities.next(last);
    }

    function getPricePerShare() external view returns (uint256) {
        return _getPricePerShare();
    }

    function positionSize(
        uint256 maturity,
        uint256 strike
    ) external view returns (uint256) {
        return UnderwriterVaultStorage.layout().positionSizes[maturity][strike];
    }

    function lastSpreadUnlockUpdate() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().lastSpreadUnlockUpdate;
    }

    function spreadUnlockingRate() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().spreadUnlockingRate;
    }

    function spreadUnlockingTicks(
        uint256 maturity
    ) external view returns (uint256) {
        return UnderwriterVaultStorage.layout().spreadUnlockingTicks[maturity];
    }

    function totalLockedAssets() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().totalLockedAssets;
    }

    function totalLockedSpread() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    function afterBuy(
        uint256 maturity,
        uint256 premium,
        uint256 secondsToExpiration,
        uint256 size,
        uint256 spread,
        uint256 strike
    ) external {
        afterBuyStruct memory intel = afterBuyStruct(
            maturity,
            premium,
            secondsToExpiration,
            size,
            spread,
            strike
        );
        _afterBuy(intel);
    }
}

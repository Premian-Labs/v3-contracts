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

    struct MaturityInfo {
        uint256 maturity;
        uint256[] strikes;
        uint256[] sizes;
    }

    constructor(
        address oracleAddress,
        address factoryAddress
    ) UnderwriterVault(oracleAddress, factoryAddress) {}

    function getMaturityAfterTimestamp(
        uint256 timestamp
    ) external view returns (uint256) {
        return _getMaturityAfterTimestamp(timestamp);
    }

    function getNumberOfUnexpiredListings() external view returns (uint256) {
        return _getNumberOfUnexpiredListings();
    }

    function getTotalFairValue() external view returns (uint256) {
        return _getTotalFairValue();
    }

    function getTotalLockedSpread() external view returns (uint256) {
        return _getTotalLockedSpread();
    }

    function increasePositionSize(
        uint256 maturity,
        uint256 strike,
        uint256 posSize
    ) external onlyOwner {
        UnderwriterVaultStorage.layout().positionSizes[maturity][
            strike
        ] += posSize;
    }

    function setLastSpreadUnlockUpdate(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().lastSpreadUnlockUpdate = value;
    }

    function getMinMaturity() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().minMaturity;
    }

    function setMinMaturity(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().minMaturity = value;
    }

    function setMaxMaturity(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().maxMaturity = value;
    }

    function logListingsAndSizes() external view {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        console.log("Min. Maturity: ", l.minMaturity);

        uint256 current = l.minMaturity;

        while (current <= l.maxMaturity) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                console.log("Maturity: ", current);
                console.log("Strike: ", l.maturityToStrikes[current].at(i));
                console.log(
                    "Size: ",
                    l.positionSizes[current][l.maturityToStrikes[current].at(i)]
                );
            }

            if (current > l.maturities.next(current)) {
                break;
            }

            current = l.maturities.next(current);
        }

        console.log("Max. Maturity: ", l.maxMaturity);
    }

    function setListingsAndSizes(
        MaturityInfo[] memory infos
    ) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 n = infos.length;

        // Setup data
        l.minMaturity = infos[0].maturity;
        uint256 current = 0;

        for (uint256 i = 0; i < n; i++) {
            l.maturities.insertAfter(current, infos[i].maturity);
            current = infos[i].maturity;

            for (uint256 j = 0; j < infos[i].strikes.length; j++) {
                l.maturityToStrikes[current].add(infos[i].strikes[j]);
                l.positionSizes[current][infos[i].strikes[j]] += infos[i].sizes[
                    j
                ];
            }
        }

        l.maxMaturity = current;
    }

    function clearListingsAndSizes() external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 current = l.minMaturity;

        uint256 next;

        while (current <= l.maxMaturity) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                l.positionSizes[current][
                    l.maturityToStrikes[current].at(i)
                ] = 0;

                l.maturityToStrikes[current].remove(
                    l.maturityToStrikes[current].at(i)
                );
            }

            next = l.maturities.next(current);
            if (current > next) {
                l.maturities.remove(current);
                break;
            }

            l.maturities.remove(current);
            current = next;
        }

        l.maxMaturity = 0;
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

    function getAvailableAssets() external view returns (uint256) {
        return _availableAssets();
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

    function calculateClevel(
        uint256 utilisation,
        uint256 alphaClevel,
        uint256 minClevel,
        uint256 maxClevel
    ) external pure returns (uint256) {
        return _calculateClevel(utilisation, alphaClevel, minClevel, maxClevel);
    }

    function getClevel(uint256 collateralAmt) external view returns (uint256) {
        return _getClevel(collateralAmt);
    }

    function addListing(uint256 strike, uint256 maturity) external {
        return _addListing(strike, maturity);
    }

    function getFactoryAddress(
        uint256 strike,
        uint256 maturity
    ) external view returns (address) {
        return _getFactoryAddress(strike, maturity);
    }

    function isValidListing(
        uint256 spotPrice,
        uint256 strike,
        uint256 maturity,
        uint256 tau,
        uint256 sigma
    ) external view returns (address) {
        return _isValidListing(spotPrice, strike, maturity, tau, sigma);
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

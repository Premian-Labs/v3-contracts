// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UnderwriterVault, SolidStateERC4626} from "../../../vaults/underwriter/UnderwriterVault.sol";
import {UnderwriterVaultStorage} from "../../../vaults/underwriter/UnderwriterVaultStorage.sol";

import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {ERC20BaseStorage} from "@solidstate/contracts/token/ERC20/base/ERC20BaseStorage.sol";
import {OptionMath} from "../../../libraries/OptionMath.sol";
import {IPool} from "../../../pool/IPool.sol";
import {UD60x18} from "../../../libraries/prbMath/UD60x18.sol";
import {IPoolFactory} from "../../../factory/IPoolFactory.sol";

contract UnderwriterVaultMock is UnderwriterVault {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSet for *;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;
    using UD60x18 for uint256;

    struct MaturityInfo {
        uint256 maturity;
        uint256[] strikes;
        uint256[] sizes;
    }

    EnumerableSet.AddressSet internal employedPools;

    constructor(
        address oracleAddress,
        address factoryAddress
    ) UnderwriterVault(oracleAddress, factoryAddress) {}

    function getMaturityAfterTimestamp(
        uint256 timestamp
    ) external view returns (uint256) {
        return _getMaturityAfterTimestamp(timestamp);
    }

    function getNumberOfUnexpiredListings(
        uint256 timestamp
    ) external view returns (uint256) {
        return _getNumberOfUnexpiredListings(timestamp);
    }

    function getTotalFairValueExpired(
        uint256 timestamp
    ) external view returns (uint256) {
        return _getTotalFairValueExpired(timestamp);
    }

    function getTotalFairValueUnexpired(
        uint256 timestamp,
        uint256 spot
    ) external view returns (uint256) {
        return _getTotalFairValueUnexpired(timestamp, spot);
    }

    function getTotalFairValue() external view returns (uint256) {
        return _getTotalFairValue();
    }

    function getNumberOfListings() external view returns (uint256) {
        return _getNumberOfListings();
    }

    function _getNumberOfListings() internal view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 current = l.minMaturity;
        uint256 n = 0;

        while (current <= l.maxMaturity && current != 0) {
            n += l.maturityToStrikes[current].length();
            current = l.maturities.next(current);
        }
        return n;
    }

    function getNumberOfListingsOnMaturity(
        uint256 maturity
    ) external view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        if (!l.maturities.contains(maturity)) return 0;
        return l.maturityToStrikes[maturity].length();
    }

    function contains(
        uint256 strike,
        uint256 maturity
    ) external view returns (bool) {
        return _contains(strike, maturity);
    }

    function updateState() external {
        return _updateState();
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

    function decreasePositionSize(
        uint256 maturity,
        uint256 strike,
        uint256 posSize
    ) external onlyOwner {
        UnderwriterVaultStorage.layout().positionSizes[maturity][
            strike
        ] -= posSize;
    }

    function getPositionSize(
        uint256 strike,
        uint256 maturity
    ) external view returns (uint256) {
        return UnderwriterVaultStorage.layout().positionSizes[maturity][strike];
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

    function getMaxMaturity() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().maxMaturity;
    }

    function setMaxMaturity(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().maxMaturity = value;
    }

    function setIsCall(bool value) external onlyOwner {
        UnderwriterVaultStorage.layout().isCall = value;
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

        l.minMaturity = 0;
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
        IERC20(_asset()).transfer(address(1), value);
    }

    function increaseTotalLockedSpread(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().totalLockedSpread += value;
    }

    function increaseTotalShares(uint256 value) external onlyOwner {
        ERC20BaseStorage.Layout storage l = ERC20BaseStorage.layout();
        l.totalSupply += value;
    }

    function mintMock(address receiver, uint256 value) external onlyOwner {
        _mint(receiver, value);
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

    function settleMaturity(uint256 maturity) external {
        _settleMaturity(maturity);
    }

    function calculateClevel(
        uint256 utilisation,
        uint256 alphaClevel,
        uint256 minClevel,
        uint256 maxClevel
    ) external pure returns (uint256) {
        return _calculateCLevel(utilisation, alphaClevel, minClevel, maxClevel);
    }

    function getClevel(uint256 collateralAmt) external view returns (uint256) {
        return _getCLevel(collateralAmt);
    }

    function addListing(uint256 strike, uint256 maturity) external {
        return _addListing(strike, maturity);
    }

    function removeListing(uint256 strike, uint256 maturity) external {
        return _removeListing(strike, maturity);
    }

    function getFactoryAddress(
        uint256 strike,
        uint256 maturity
    ) external view returns (address) {
        return _getFactoryAddress(strike, maturity);
    }

    function ensureSupportedListing(
        uint256 spotPrice,
        uint256 strike,
        uint256 tau,
        uint256 sigma,
        uint256 rfRate
    ) external {
        _ensureSupportedListing(spotPrice, strike, tau, sigma, rfRate);
    }

    function afterBuy(
        uint256 maturity,
        uint256 premium,
        uint256 secondsToExpiration,
        uint256 size,
        uint256 spread,
        uint256 strike
    ) external {
        AfterBuyArgs memory intel = AfterBuyArgs(
            maturity,
            premium,
            secondsToExpiration,
            size,
            spread,
            strike
        );
        _afterBuy(intel);
    }

    function getSpotPrice() public view returns (uint256) {
        return _getSpotPrice();
    }

    function getSpotPrice(uint256 timestamp) public view returns (uint256) {
        return _getSpotPrice(timestamp);
    }

    function getTradeBounds()
        public
        view
        returns (uint256, uint256, int256, int256)
    {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return (l.minDTE, l.maxDTE, l.minDelta, l.maxDelta);
    }

    function getClevelParams()
        public
        view
        returns (uint256, uint256, uint256, uint256)
    {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return (l.minCLevel, l.maxCLevel, l.alphaCLevel, l.hourlyDecayDiscount);
    }

    function getLastTradeTimestamp() public view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.lastTradeTimestamp;
    }

    function setMaxClevel(uint256 maxCLevel) public {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.maxCLevel = maxCLevel;
    }

    function setAlphaCLevel(uint256 alphaCLevel) public {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.alphaCLevel = alphaCLevel;
    }

    function getDelta(
        uint256 spotPrice,
        uint256 strike,
        uint256 tau,
        uint256 sigma,
        uint256 rfRate,
        bool isCallOption
    ) public pure returns (int256) {
        int256 delta = OptionMath.optionDelta(
            spotPrice,
            strike,
            tau,
            sigma,
            rfRate,
            isCallOption
        );

        return delta;
    }

    function getBlackScholesPrice(
        uint256 spotPrice,
        uint256 strike,
        uint256 tau,
        uint256 sigma,
        uint256 rfRate,
        bool isCallOption
    ) public pure returns (uint256) {
        uint256 price = OptionMath.blackScholesPrice(
            spotPrice,
            strike,
            tau,
            sigma,
            rfRate,
            isCallOption
        );

        return price;
    }

    function isCall() public view returns (bool) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.isCall;
    }

    function maxMaturity() public view returns (uint256) {
        return UnderwriterVaultStorage.layout().maxMaturity;
    }

    function minMaturity() public view returns (uint256) {
        return UnderwriterVaultStorage.layout().minMaturity;
    }

    function mintFromPool(
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) public {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        address listingAddr = _getFactoryAddress(strike, maturity);
        uint256 allowance = 2 * size;
        if (!l.isCall) {
            allowance = allowance.mul(strike);
        }
        IERC20(_asset()).approve(listingAddr, allowance);
        IPool(listingAddr).writeFrom(address(this), msg.sender, size);
    }

    function getActivePoolAddresses() public returns (address[] memory) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        uint256 maturity = l.minMaturity;
        uint256 n = _getNumberOfListings();
        address[] memory addresses = new address[](n);

        while (maturity != 0) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[maturity].length();
                i++
            ) {
                IPoolFactory.PoolKey memory _poolKey;
                _poolKey.base = l.base;
                _poolKey.quote = l.quote;
                _poolKey.oracleAdapter = l.oracleAdapter;
                _poolKey.strike = l.maturityToStrikes[maturity].at(i);
                _poolKey.maturity = uint64(maturity);
                _poolKey.isCallPool = l.isCall;
                address listingAddr = IPoolFactory(FACTORY).getPoolAddress(
                    _poolKey
                );
                addresses[i] = listingAddr;
                if (!employedPools.contains(listingAddr))
                    employedPools.add(listingAddr);
            }
            maturity = l.maturities.next(maturity);
        }
        return addresses;
    }

    function getEmployedPools() external view returns (address[] memory) {
        uint256 n = employedPools.length();
        address[] memory addresses = new address[](n);
        for (uint256 i = 0; i < employedPools.length(); i++)
            addresses[i] = employedPools.at(i);
        return addresses;
    }
}

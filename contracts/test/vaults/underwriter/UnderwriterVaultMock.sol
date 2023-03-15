// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {UnderwriterVault, SolidStateERC4626} from "../../../vaults/underwriter/UnderwriterVault.sol";
import {UnderwriterVaultStorage} from "../../../vaults/underwriter/UnderwriterVaultStorage.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {ERC20BaseStorage} from "@solidstate/contracts/token/ERC20/base/ERC20BaseStorage.sol";
import {OptionMath} from "../../../libraries/OptionMath.sol";
import {IPool} from "../../../pool/IPool.sol";
import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {IPoolFactory} from "../../../factory/IPoolFactory.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";
import {SD59x18} from "@prb/math/src/SD59x18.sol";
import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../../../libraries/DoublyLinkedListUD60x18.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../../libraries/EnumerableSetUD60x18.sol";
import {PRBMathExtra} from "../../../libraries/PRBMathExtra.sol";

contract UnderwriterVaultMock is UnderwriterVault {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSetUD60x18 for EnumerableSet.Bytes32Set;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;
    using PRBMathExtra for UD60x18;
    using PRBMathExtra for SD59x18;

    struct MaturityInfo {
        uint256 maturity;
        UD60x18[] strikes;
        UD60x18[] sizes;
    }

    EnumerableSet.AddressSet internal employedPools;

    constructor(
        address oracleAddress,
        address factoryAddress,
        address routerAddress
    ) UnderwriterVault(oracleAddress, factoryAddress, routerAddress) {}

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

    function getTotalLiabilitiesExpired(
        uint256 timestamp
    ) external view returns (UD60x18) {
        return _getTotalLiabilitiesExpired(timestamp);
    }

    function getTotalLiabilitiesUnexpired(
        uint256 timestamp,
        UD60x18 spot
    ) external view returns (UD60x18) {
        return _getTotalLiabilitiesUnexpired(timestamp, spot);
    }

    function getTotalLiabilities() external view returns (UD60x18) {
        return _getTotalLiabilities();
    }

    function getTotalFairValue() external view returns (UD60x18) {
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
        UD60x18 strike,
        uint256 maturity
    ) external view returns (bool) {
        return _contains(strike, maturity);
    }

    function updateState() external {
        return _updateState();
    }

    function getTotalLockedSpread() external view returns (UD60x18) {
        return _getTotalLockedSpread();
    }

    function increasePositionSize(
        uint256 maturity,
        UD60x18 strike,
        UD60x18 posSize
    ) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.positionSizes[maturity][strike] =
            l.positionSizes[maturity][strike] +
            posSize;
    }

    function decreasePositionSize(
        uint256 maturity,
        UD60x18 strike,
        UD60x18 posSize
    ) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.positionSizes[maturity][strike] =
            l.positionSizes[maturity][strike] -
            posSize;
    }

    function getPositionSize(
        UD60x18 strike,
        uint256 maturity
    ) external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().positionSizes[maturity][strike];
    }

    function setTotalLockedAssets(UD60x18 value) external onlyOwner {
        UnderwriterVaultStorage.layout().totalLockedAssets = value;
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
                l.positionSizes[current][infos[i].strikes[j]] =
                    l.positionSizes[current][infos[i].strikes[j]] +
                    infos[i].sizes[j];
            }
        }

        l.maxMaturity = current;
    }

    function clearListingsAndSizes() external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();

        uint256 current = l.minMaturity;

        while (current <= l.maxMaturity) {
            for (
                uint256 i = 0;
                i < l.maturityToStrikes[current].length();
                i++
            ) {
                l.positionSizes[current][
                    l.maturityToStrikes[current].at(i)
                ] = ZERO;

                l.maturityToStrikes[current].remove(
                    l.maturityToStrikes[current].at(i)
                );
            }

            uint256 next = l.maturities.next(current);
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

    function insertStrike(uint256 maturity, UD60x18 strike) external onlyOwner {
        UnderwriterVaultStorage.layout().maturityToStrikes[maturity].add(
            strike
        );
    }

    function increaseSpreadUnlockingRate(UD60x18 value) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.spreadUnlockingRate = l.spreadUnlockingRate + value;
    }

    function increaseSpreadUnlockingTick(
        uint256 maturity,
        UD60x18 value
    ) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.spreadUnlockingTicks[maturity] =
            l.spreadUnlockingTicks[maturity] +
            value;
    }

    function increaseTotalLockedAssets(UD60x18 value) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalLockedAssets = l.totalLockedAssets + value;
        IERC20(_asset()).transfer(address(1), value.unwrap());
    }

    function increaseTotalLockedSpread(UD60x18 value) external onlyOwner {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalLockedSpread = l.totalLockedSpread + value;
    }

    function increaseTotalShares(uint256 value) external onlyOwner {
        ERC20BaseStorage.Layout storage l = ERC20BaseStorage.layout();
        l.totalSupply += value;
    }

    function mintMock(address receiver, uint256 value) external onlyOwner {
        _mint(receiver, value);
    }

    function getAvailableAssets() external view returns (UD60x18) {
        return _availableAssets();
    }

    function getPricePerShare() external view returns (UD60x18) {
        return _getPricePerShare();
    }

    function positionSize(
        uint256 maturity,
        UD60x18 strike
    ) external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().positionSizes[maturity][strike];
    }

    function lastSpreadUnlockUpdate() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().lastSpreadUnlockUpdate;
    }

    function spreadUnlockingRate() external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().spreadUnlockingRate;
    }

    function spreadUnlockingTicks(
        uint256 maturity
    ) external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().spreadUnlockingTicks[maturity];
    }

    function totalLockedAssets() external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().totalLockedAssets;
    }

    function totalLockedSpread() external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    function settleMaturity(uint256 maturity) external {
        _settleMaturity(maturity);
    }

    function calculateClevel(
        UD60x18 utilisation,
        UD60x18 alphaClevel,
        UD60x18 minClevel,
        UD60x18 maxClevel
    ) external pure returns (UD60x18) {
        return _calculateCLevel(utilisation, alphaClevel, minClevel, maxClevel);
    }

    function getClevel(UD60x18 collateralAmt) external view returns (UD60x18) {
        return _getCLevel(collateralAmt);
    }

    function addListing(UD60x18 strike, uint256 maturity) external {
        return _addListing(strike, maturity);
    }

    function removeListing(UD60x18 strike, uint256 maturity) external {
        return _removeListing(strike, maturity);
    }

    function getFactoryAddress(
        UD60x18 strike,
        uint256 maturity
    ) external view returns (address) {
        return _getFactoryAddress(strike, maturity);
    }

    function ensureSupportedListing(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 tau,
        UD60x18 sigma,
        UD60x18 rfRate
    ) external {
        _ensureSupportedListing(spot, strike, tau, sigma, rfRate);
    }

    function afterBuy(
        uint256 maturity,
        UD60x18 premium,
        uint256 secondsToExpiration,
        UD60x18 size,
        UD60x18 spread,
        UD60x18 strike
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

    function getSpotPrice() public view returns (UD60x18) {
        return _getSpotPrice();
    }

    function getSpotPrice(uint256 timestamp) public view returns (UD60x18) {
        return _getSpotPrice(timestamp);
    }

    function getTradeBounds()
        public
        view
        returns (UD60x18, UD60x18, SD59x18, SD59x18)
    {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return (l.minDTE, l.maxDTE, l.minDelta, l.maxDelta);
    }

    function getClevelParams()
        public
        view
        returns (UD60x18, UD60x18, UD60x18, UD60x18)
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

    function setMaxClevel(UD60x18 maxCLevel) public {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.maxCLevel = maxCLevel;
    }

    function setAlphaCLevel(UD60x18 alphaCLevel) public {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.alphaCLevel = alphaCLevel;
    }

    function getDelta(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 tau,
        UD60x18 sigma,
        UD60x18 rfRate,
        bool isCallOption
    ) public pure returns (SD59x18) {
        return
            OptionMath.optionDelta(
                spot,
                strike,
                tau,
                sigma,
                rfRate,
                isCallOption
            );
    }

    function getBlackScholesPrice(
        UD60x18 spot,
        UD60x18 strike,
        UD60x18 tau,
        UD60x18 sigma,
        UD60x18 rfRate,
        bool isCallOption
    ) public pure returns (UD60x18) {
        return
            OptionMath.blackScholesPrice(
                spot,
                strike,
                tau,
                sigma,
                rfRate,
                isCallOption
            );
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
        UD60x18 strike,
        uint256 maturity,
        UD60x18 size
    ) public {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        address listingAddr = _getFactoryAddress(strike, maturity);
        UD60x18 allowance = UD60x18.wrap(2e18) * size;
        if (!l.isCall) {
            allowance = allowance * strike;
        }
        IERC20(_asset()).approve(ROUTER, allowance.unwrap());

        IPool(listingAddr).writeFrom(address(this), msg.sender, size);
        l.totalLockedAssets = l.totalLockedAssets + size;
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

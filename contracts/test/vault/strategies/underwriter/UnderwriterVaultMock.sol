// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SD59x18} from "@prb/math/SD59x18.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {ERC20BaseStorage} from "@solidstate/contracts/token/ERC20/base/ERC20BaseStorage.sol";

import {IPoolFactory} from "../../../../factory/IPoolFactory.sol";
import {ZERO} from "../../../../libraries/Constants.sol";
import {DoublyLinkedList} from "../../../../libraries/DoublyLinkedListUD60x18.sol";
import {EnumerableSetUD60x18, EnumerableSet} from "../../../../libraries/EnumerableSetUD60x18.sol";
import {OptionMath} from "../../../../libraries/OptionMath.sol";
import {Permit2} from "../../../../libraries/Permit2.sol";
import {IPool} from "../../../../pool/IPool.sol";
import {UnderwriterVault} from "../../../../vault/strategies/underwriter/UnderwriterVault.sol";
import {UnderwriterVaultStorage} from "../../../../vault/strategies/underwriter/UnderwriterVaultStorage.sol";

contract UnderwriterVaultMock is UnderwriterVault {
    using DoublyLinkedList for DoublyLinkedList.Uint256List;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSetUD60x18 for EnumerableSet.Bytes32Set;
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;
    using SafeCast for int256;
    using SafeCast for uint256;

    struct MaturityInfo {
        uint256 maturity;
        UD60x18[] strikes;
        UD60x18[] sizes;
    }

    // Mock variables
    uint256 mockTimestamp;
    UD60x18 mockSpot;

    constructor(
        address vaultRegistry,
        address feeReceiver,
        address oracleAddress,
        address factoryAddress,
        address routerAddress
    )
        UnderwriterVault(
            vaultRegistry,
            feeReceiver,
            oracleAddress,
            factoryAddress,
            routerAddress
        )
    {}

    function _getBlockTimestamp() internal view override returns (uint256) {
        return mockTimestamp == 0 ? block.timestamp : mockTimestamp;
    }

    function setTimestamp(uint256 newTimestamp) external {
        mockTimestamp = newTimestamp;
    }

    function _getSpotPrice() internal view override returns (UD60x18) {
        return mockSpot == ZERO ? super._getSpotPrice() : mockSpot;
    }

    function setSpotPrice(UD60x18 newSpot) external {
        mockSpot = newSpot;
    }

    function assetDecimals() external view returns (uint8) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.assetDecimals();
    }

    function convertAssetToUD60x18(
        uint256 value
    ) external view returns (UD60x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetToUD60x18(value);
    }

    function convertAssetToSD59x18(
        int256 value
    ) external view returns (SD59x18) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetToSD59x18(value);
    }

    function convertAssetFromUD60x18(
        UD60x18 value
    ) external view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetFromUD60x18(value);
    }

    function convertAssetFromSD59x18(
        SD59x18 value
    ) external view returns (int256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.convertAssetFromSD59x18(value);
    }

    function getMaturityAfterTimestamp(
        uint256 timestamp
    ) external view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.getMaturityAfterTimestamp(timestamp);
    }

    function getNumberOfUnexpiredListings(
        uint256 timestamp
    ) external view returns (uint256) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.getNumberOfUnexpiredListings(timestamp);
    }

    function getTotalLiabilitiesExpired() external view returns (UD60x18) {
        return _getTotalLiabilitiesExpired();
    }

    function getTotalLiabilitiesUnexpired() external view returns (UD60x18) {
        return _getTotalLiabilitiesUnexpired();
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

    function updateState() external {
        return _updateState();
    }

    function getLockedSpreadInternal()
        external
        view
        returns (LockedSpreadInternal memory)
    {
        return _getLockedSpreadInternal();
    }

    function increasePositionSize(
        uint256 maturity,
        UD60x18 strike,
        UD60x18 posSize
    ) external {
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
    ) external {
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

    function setLastTradeTimestamp(uint256 timestamp) external {
        UnderwriterVaultStorage.layout().lastTradeTimestamp = timestamp;
    }

    function setTotalLockedAssets(UD60x18 value) external {
        UnderwriterVaultStorage.layout().totalLockedAssets = value;
    }

    function setLastSpreadUnlockUpdate(uint256 value) external {
        UnderwriterVaultStorage.layout().lastSpreadUnlockUpdate = value;
    }

    function getMinMaturity() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().minMaturity;
    }

    function setMinMaturity(uint256 value) external {
        UnderwriterVaultStorage.layout().minMaturity = value;
    }

    function getMaxMaturity() external view returns (uint256) {
        return UnderwriterVaultStorage.layout().maxMaturity;
    }

    function setMaxMaturity(uint256 value) external {
        UnderwriterVaultStorage.layout().maxMaturity = value;
    }

    function setIsCall(bool value) external {
        UnderwriterVaultStorage.layout().isCall = value;
    }

    function setListingsAndSizes(MaturityInfo[] memory infos) external {
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

    function clearListingsAndSizes() external {
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

    function insertMaturity(uint256 maturity, uint256 newMaturity) external {
        UnderwriterVaultStorage.layout().maturities.insertAfter(
            maturity,
            newMaturity
        );
    }

    function insertStrike(uint256 maturity, UD60x18 strike) external {
        UnderwriterVaultStorage.layout().maturityToStrikes[maturity].add(
            strike
        );
    }

    function increaseSpreadUnlockingRate(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.spreadUnlockingRate = l.spreadUnlockingRate + value;
    }

    function increaseSpreadUnlockingTick(
        uint256 maturity,
        UD60x18 value
    ) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.spreadUnlockingTicks[maturity] =
            l.spreadUnlockingTicks[maturity] +
            value;
    }

    function increaseTotalLockedAssetsNoTransfer(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalLockedAssets = l.totalLockedAssets + value;
    }

    function increaseTotalLockedAssets(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalLockedAssets = l.totalLockedAssets + value;
        uint256 transfer = l.convertAssetFromUD60x18(value);
        IERC20(_asset()).transfer(address(1), transfer);
    }

    function increaseTotalLockedSpread(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalLockedSpread = l.totalLockedSpread + value;
    }

    function increaseTotalShares(uint256 value) external {
        ERC20BaseStorage.Layout storage l = ERC20BaseStorage.layout();
        l.totalSupply += value;
    }

    function setTotalAssets(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalAssets = value;
    }

    function increaseTotalAssets(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.totalAssets = l.totalAssets + value;
    }

    function mintMock(address receiver, uint256 value) external {
        _mint(receiver, value);
    }

    function getAvailableAssets() external view returns (UD60x18) {
        return _availableAssetsUD60x18();
    }

    function getPricePerShare() external view returns (UD60x18) {
        return _getPricePerShareUD60x18();
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

    function contains(
        UD60x18 strike,
        uint256 maturity
    ) external view returns (bool) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.contains(strike, maturity);
    }

    function addListing(UD60x18 strike, uint256 maturity) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.addListing(strike, maturity);
    }

    function removeListing(UD60x18 strike, uint256 maturity) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        return l.removeListing(strike, maturity);
    }

    function getPoolAddress(
        UD60x18 strike,
        uint256 maturity
    ) external view returns (address) {
        return _getPoolAddress(strike, maturity);
    }

    function afterBuy(
        UD60x18 strike,
        uint256 maturity,
        UD60x18 size,
        UD60x18 spread
    ) external {
        _afterBuy(strike, maturity, size, spread);
    }

    function getSpotPrice() public view returns (UD60x18) {
        return _getSpotPrice();
    }

    function getSettlementPrice(
        uint256 timestamp
    ) public view returns (UD60x18) {
        return _getSettlementPrice(timestamp);
    }

    function getTradeBounds()
        public
        view
        returns (UD60x18, UD60x18, UD60x18, UD60x18)
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
        address pool = _getPoolAddress(strike, maturity);
        UD60x18 allowance = UD60x18.wrap(2e18) * size;
        UD60x18 locked;
        if (!l.isCall) {
            allowance = allowance * strike;
            locked = size * strike;
        } else {
            locked = size;
        }
        IERC20(_asset()).approve(ROUTER, allowance.unwrap());

        UD60x18 mintingFee = l.convertAssetToUD60x18(
            IPool(pool).takerFee(address(0), size, 0, true)
        );

        IPool(pool).writeFrom(
            address(this),
            msg.sender,
            size,
            Permit2.emptyPermit()
        );

        l.totalLockedAssets = l.totalLockedAssets + locked;
        l.totalAssets = l.totalAssets - mintingFee;
    }

    function ensureTradeableWithVault(
        bool isCallVault,
        bool isCallOption,
        bool isBuy
    ) external pure {
        _ensureTradeableWithVault(isCallVault, isCallOption, isBuy);
    }

    function ensureValidOption(UD60x18 strike, uint256 maturity) external view {
        _ensureValidOption(strike, maturity);
    }

    function ensureSufficientFunds(
        bool isCallVault,
        UD60x18 strike,
        UD60x18 size,
        UD60x18 availableAssets
    ) external pure {
        _ensureSufficientFunds(isCallVault, strike, size, availableAssets);
    }

    function ensureWithinDTEBounds(
        UD60x18 value,
        UD60x18 minimum,
        UD60x18 maximum
    ) external pure {
        _ensureWithinDTEBounds(value, minimum, maximum);
    }

    function ensureWithinDeltaBounds(
        UD60x18 value,
        UD60x18 minimum,
        UD60x18 maximum
    ) external pure {
        _ensureWithinDeltaBounds(value, minimum, maximum);
    }

    function computeCLevel(
        UD60x18 utilisation,
        UD60x18 duration,
        UD60x18 alpha,
        UD60x18 minCLevel,
        UD60x18 maxCLevel,
        UD60x18 decayRate
    ) external pure returns (UD60x18) {
        return
            _computeCLevel(
                utilisation,
                duration,
                alpha,
                minCLevel,
                maxCLevel,
                decayRate
            );
    }

    function setProtocolFees(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.protocolFees = value;
    }

    function balanceOfAsset(address owner) external view returns (uint256) {
        return _balanceOfAsset(owner);
    }

    function setManagementFeeRate(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.managementFeeRate = value;
    }

    function setPerformanceFeeRate(UD60x18 value) external {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage
            .layout();
        l.performanceFeeRate = value;
    }

    function getProtocolFees() external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().protocolFees;
    }

    function setNetUserDeposit(address owner, uint256 value) external {
        UnderwriterVaultStorage.layout().netUserDeposits[owner] = UD60x18.wrap(
            value
        );
    }

    function getNetUserDeposit(address owner) external view returns (UD60x18) {
        return UnderwriterVaultStorage.layout().netUserDeposits[owner];
    }

    function setTimeOfDeposit(address owner, uint256 value) external {
        UnderwriterVaultStorage.layout().timeOfDeposit[owner] = value;
    }

    function getTimeOfDeposit(address owner) external view returns (uint256) {
        return UnderwriterVaultStorage.layout().timeOfDeposit[owner];
    }

    function maxTransferableShares(
        FeeInternal memory vars
    ) external pure returns (uint256) {
        return _maxTransferableShares(vars).unwrap();
    }

    function getAveragePricePerShare(
        address owner
    ) external view returns (uint256) {
        return _getAveragePricePerShareUD60x18(owner).unwrap();
    }

    function beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) external {
        _beforeTokenTransfer(from, to, amount);
    }

    function claimFees() external {
        _claimFees();
    }

    function getFeeInternal(
        address from,
        UD60x18 shares,
        UD60x18 pps
    ) external view returns (FeeInternal memory) {
        return _getFeeInternal(from, shares, pps);
    }

    function afterDeposit(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) external {
        return _afterDeposit(receiver, assetAmount, shareAmount);
    }

    function beforeWithdraw(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) external {
        return _beforeWithdraw(receiver, assetAmount, shareAmount);
    }

    function updateTimeOfDeposit(
        address owner,
        uint256 shareBalanceBefore,
        uint256 shareAmount
    ) external {
        _updateTimeOfDeposit(owner, shareBalanceBefore, shareAmount);
    }
}

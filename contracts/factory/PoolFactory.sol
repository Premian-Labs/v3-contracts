// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";

import {UD60x18} from "../libraries/prbMath/UD60x18.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

contract PoolFactory is IPoolFactory {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolFactoryStorage for PoolKey;
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for int256;
    using SafeCast for uint256;
    using UD60x18 for uint256;

    uint256 internal constant ONE = 1e18;
    address internal immutable DIAMOND;

    constructor(
        address diamond,
        uint256 discountPerPool,
        address discountAdmin
    ) {
        PoolFactoryStorage.Layout storage self = PoolFactoryStorage.layout();

        DIAMOND = diamond;

        self.discountPerPool = discountPerPool;
        self.discountAdmin = discountAdmin;
    }

    /// @inheritdoc IPoolFactory
    function isPoolDeployed(PoolKey memory k) external view returns (bool) {
        return _isPoolDeployed(k.poolKey());
    }

    function _isPoolDeployed(bytes32 poolKey) internal view returns (bool) {
        return PoolFactoryStorage.layout().pools[poolKey] != address(0);
    }

    function getSpotPrice(
        address baseOracle,
        address quoteOracle
    ) internal view returns (uint256 price) {
        uint256 quotePrice = getSpotPrice(quoteOracle);
        uint256 basePrice = getSpotPrice(baseOracle);

        return basePrice.div(quotePrice);
    }

    function getSpotPrice(address oracle) internal view returns (uint256) {
        // TODO: Add spot price validation

        int256 price = AggregatorInterface(oracle).latestAnswer();
        if (price < 0) revert PoolFactory__NegativeSpotPrice();

        return price.toUint256();
    }

    // @inheritdoc IPoolFactory
    function initializationFee(PoolKey memory k) public view returns (uint256) {
        PoolFactoryStorage.Layout storage self = PoolFactoryStorage.layout();

        uint256 discountFactor = self.maturityCount[k.maturityKey()] +
            self.strikeCount[k.strikeKey()];
        uint256 discount = (ONE - self.discountPerPool).pow(discountFactor);
        uint256 spot = getSpotPrice(k.baseOracle, k.quoteOracle);
        uint256 fee = OptionMath.initializationFee(spot, k.strike, k.maturity);

        return fee.mul(discount);
    }

    /// @inheritdoc IPoolFactory
    function setDiscountBps(uint256 discountPerPool) external {
        PoolFactoryStorage.Layout storage self = PoolFactoryStorage.layout();

        if (msg.sender != self.discountAdmin)
            revert PoolFactory__NotAuthorized();

        self.discountPerPool = discountPerPool;

        emit SetDiscountBps(discountPerPool);
    }

    /// @inheritdoc IPoolFactory
    function setDiscountAdmin(address discountAdmin) external {
        PoolFactoryStorage.Layout storage self = PoolFactoryStorage.layout();

        if (msg.sender != self.discountAdmin)
            revert PoolFactory__NotAuthorized();

        self.discountAdmin = discountAdmin;

        emit SetDiscountAdmin(discountAdmin);
    }

    /// @inheritdoc IPoolFactory
    function deployPool(
        PoolKey memory k
    ) external returns (address poolAddress) {
        if (k.base == k.quote || k.baseOracle == k.quoteOracle)
            revert PoolFactory__IdenticalAddresses();

        if (
            k.base == address(0) ||
            k.baseOracle == address(0) ||
            k.quote == address(0) ||
            k.quoteOracle == address(0)
        ) revert PoolFactory__ZeroAddress();

        _ensureOptionStrikeIsValid(k.strike, k.baseOracle, k.quoteOracle);
        _ensureOptionMaturityIsValid(k.maturity);

        bytes32 poolKey = k.poolKey();

        if (_isPoolDeployed(poolKey)) revert PoolFactory__PoolAlreadyDeployed();

        poolAddress = address(
            new PoolProxy(
                DIAMOND,
                k.base,
                k.quote,
                k.baseOracle,
                k.quoteOracle,
                k.strike,
                k.maturity,
                k.isCallPool
            )
        );

        PoolFactoryStorage.layout().pools[poolKey] = poolAddress;
        PoolFactoryStorage.layout().strikeCount[k.strikeKey()] += 1;
        PoolFactoryStorage.layout().maturityCount[k.maturityKey()] += 1;

        emit PoolDeployed(
            k.base,
            k.quote,
            k.baseOracle,
            k.quoteOracle,
            k.strike,
            k.maturity,
            poolAddress
        );
    }

    /// @inheritdoc IPoolFactory
    function removePool(PoolKey memory k) external {
        if (k.maturity < block.timestamp) revert PoolFactory__PoolNotExpired();

        if (PoolFactoryStorage.layout().pools[k.poolKey()] != msg.sender)
            revert PoolFactory__NotAuthorized();

        PoolFactoryStorage.layout().strikeCount[k.strikeKey()] -= 1;
        PoolFactoryStorage.layout().maturityCount[k.maturityKey()] -= 1;
    }

    /// @notice Ensure that the strike price is a multiple of the strike interval, revert otherwise
    function _ensureOptionStrikeIsValid(
        uint256 strike,
        address baseOracle,
        address quoteOracle
    ) internal view {
        if (strike == 0) revert PoolFactory__OptionStrikeEqualsZero();

        uint256 basePrice = PoolStorage.getSpotPrice(baseOracle);
        uint256 quotePrice = PoolStorage.getSpotPrice(quoteOracle);
        uint256 spot = basePrice.div(quotePrice);
        uint256 strikeInterval = OptionMath.calculateStrikeInterval(spot);

        if (strike % strikeInterval != 0)
            revert PoolFactory__OptionStrikeInvalid();
    }

    /// @notice Ensure that the maturity is a valid option maturity, revert otherwise
    function _ensureOptionMaturityIsValid(uint64 maturity) internal view {
        if (maturity <= block.timestamp) revert PoolFactory__OptionExpired();

        if ((maturity % 24 hours) % 8 hours != 0)
            revert PoolFactory__OptionMaturityNot8UTC();

        uint256 ttm = OptionMath.calculateTimeToMaturity(maturity);

        if (ttm >= 3 days && ttm <= 30 days) {
            if (!OptionMath.isFriday(maturity))
                revert PoolFactory__OptionMaturityNotFriday();
        }

        if (ttm > 30 days) {
            if (!OptionMath.isLastFriday(maturity))
                revert PoolFactory__OptionMaturityNotLastFriday();
        }

        if (ttm > 365 days) revert PoolFactory__OptionMaturityExceedsMax();
    }
}

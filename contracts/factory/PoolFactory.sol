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
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for int256;
    using SafeCast for uint256;
    using UD60x18 for uint256;

    uint256 internal constant ONE = 1e18;
    address internal immutable DIAMOND;

    constructor(address diamond, uint256 discountPerPool, address discountAdmin) {
        PoolFactoryStorage.Layout storage self = PoolFactoryStorage.layout();

        DIAMOND = diamond;

        self.discountPerPool = discountPerPool;
        self.discountAdmin = discountAdmin;
    }

    /// @inheritdoc IPoolFactory
    function isPoolDeployed(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external view returns (bool) {
        bytes32 poolKey = PoolFactoryStorage.poolKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            maturity,
            isCallPool
        );
        return _isPoolDeployed(poolKey);
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
    function initializationFee(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) public view returns (uint256) {
        PoolFactoryStorage.Layout storage self = PoolFactoryStorage.layout();
        bytes32 strikeKey = PoolFactoryStorage.strikeKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            isCallPool
        );
        bytes32 maturityKey = PoolFactoryStorage.maturityKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            maturity,
            isCallPool
        );

        uint256 discountFactor = self.maturityCount[maturityKey] + self.strikeCount[strikeKey];
        uint256 discount = (ONE - self.discountPerPool).pow(discountFactor);
        uint256 spot = getSpotPrice(baseOracle, quoteOracle);
        uint256 fee = OptionMath.initializationFee(
            spot,
            strike,
            maturity
        );

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
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external returns (address poolAddress) {
        if (base == quote || baseOracle == quoteOracle)
            revert PoolFactory__IdenticalAddresses();

        if (
            base == address(0) ||
            baseOracle == address(0) ||
            quote == address(0) ||
            quoteOracle == address(0)
        ) revert PoolFactory__ZeroAddress();

        _ensureOptionStrikeIsValid(strike, baseOracle, quoteOracle);
        _ensureOptionMaturityIsValid(maturity);

        bytes32 poolKey = PoolFactoryStorage.poolKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            maturity,
            isCallPool
        );
        bytes32 strikeKey = PoolFactoryStorage.strikeKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            isCallPool
        );
        bytes32 maturityKey = PoolFactoryStorage.maturityKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            maturity,
            isCallPool
        );

        if (_isPoolDeployed(poolKey)) revert PoolFactory__PoolAlreadyDeployed();

        poolAddress = address(
            new PoolProxy(
                DIAMOND,
                base,
                quote,
                baseOracle,
                quoteOracle,
                strike,
                maturity,
                isCallPool
            )
        );

        PoolFactoryStorage.layout().pools[poolKey] = poolAddress;
        PoolFactoryStorage.layout().strikeCount[strikeKey] += 1;
        PoolFactoryStorage.layout().maturityCount[maturityKey] += 1;

        emit PoolDeployed(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            maturity,
            poolAddress
        );
    }

    /// @inheritdoc IPoolFactory
    function removePool(
        address base,
        address quote,
        address baseOracle,
        address quoteOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) external {
        if (maturity < block.timestamp)
            revert PoolFactory__PoolNotExpired();

        bytes32 poolKey = PoolFactoryStorage.poolKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            maturity,
            isCallPool
        );
        bytes32 strikeKey = PoolFactoryStorage.strikeKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            strike,
            isCallPool
        );
        bytes32 maturityKey = PoolFactoryStorage.maturityKey(
            base,
            quote,
            baseOracle,
            quoteOracle,
            maturity,
            isCallPool
        );

        if (PoolFactoryStorage.layout().pools[poolKey] != msg.sender)
            revert PoolFactory__NotAuthorized();

        PoolFactoryStorage.layout().strikeCount[strikeKey] -= 1;
        PoolFactoryStorage.layout().maturityCount[maturityKey] -= 1;
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

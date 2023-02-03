// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";

import {OptionMath} from "../libraries/OptionMath.sol";

contract PoolFactory is IPoolFactory {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for uint256;

    address internal immutable DIAMOND;

    constructor(address diamond) {
        DIAMOND = diamond;
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

    /// @notice Ensure that the strike price is a multiple of the strike interval, revert otherwise
    function _ensureOptionStrikeIsValid(
        uint256 strike,
        address baseOracle,
        address quoteOracle
    ) internal view {
        if (strike == 0) revert PoolFactory__OptionStrikeEqualsZero();

        int256 basePrice = PoolStorage.getSpotPrice(baseOracle);
        int256 quotePrice = PoolStorage.getSpotPrice(quoteOracle);

        int256 spot = (basePrice * 1e18) / quotePrice;
        int256 strikeInterval = OptionMath.calculateStrikeInterval(spot);

        if (strike.toInt256() % strikeInterval != 0)
            revert PoolFactory__OptionStrikeInvalid();
    }

    /// @notice Ensure that the maturity is a valid option maturity, revert otherwise
    function _ensureOptionMaturityIsValid(uint64 maturity) internal view {
        if (maturity <= block.timestamp) revert PoolFactory__OptionExpired();

        if ((maturity % 24 hours) % 8 hours != 0)
            revert PoolFactory__OptionMaturityNot8UTC();

        uint256 ttm = OptionMath.calculateTimeToMaturity(maturity);

        if (ttm >= 3 days && ttm <= 31 days) {
            if (!OptionMath.isFriday(maturity))
                revert PoolFactory__OptionMaturityNotFriday();
        }

        if (ttm > 31 days) {
            if (!OptionMath.isLastFriday(maturity))
                revert PoolFactory__OptionMaturityNotLastFriday();
        }

        if (ttm > 365 days) revert PoolFactory__OptionMaturityExceedsMax();
    }
}

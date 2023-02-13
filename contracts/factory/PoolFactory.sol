// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";

import {SD59x18} from "../libraries/prbMath/SD59x18.sol";
import {UD60x18} from "../libraries/prbMath/UD60x18.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

contract PoolFactory is IPoolFactory, SafeOwnable {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolFactoryStorage for PoolKey;
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for int256;
    using SafeCast for uint256;
    using SD59x18 for int256;
    using UD60x18 for uint256;

    uint256 internal constant ONE = 1e18;
    address internal immutable DIAMOND;
    // Chainlink price oracle for the Native/USD (ETH/USD) pair
    address internal immutable NATIVE_USD_ORACLE;

    constructor(address diamond, address nativeUsdOracle) {
        DIAMOND = diamond;
        NATIVE_USD_ORACLE = nativeUsdOracle;
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

        // TODO Replace with adapter, decimals should not be hard-coded

        return price.toUint256() * 1e10;
    }

    // @inheritdoc IPoolFactory
    function initializationFee(PoolKey memory k) public view returns (uint256) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        uint256 discountFactor = l.maturityCount[k.maturityKey()] +
            l.strikeCount[k.strikeKey()];
        uint256 discount = (ONE - l.discountPerPool)
            .toInt256()
            .pow(discountFactor.toInt256())
            .toUint256();
        uint256 spot = getSpotPrice(k.baseOracle, k.quoteOracle);
        uint256 fee = OptionMath.initializationFee(spot, k.strike, k.maturity);
        uint256 nativeUsdPrice = getSpotPrice(NATIVE_USD_ORACLE);

        return fee.mul(discount).div(nativeUsdPrice);
    }

    /// @inheritdoc IPoolFactory
    function setDiscountPerPool(uint256 discountPerPool) external onlyOwner {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();
        l.discountPerPool = discountPerPool;
        emit SetDiscountPerPool(discountPerPool);
    }

    /// @inheritdoc IPoolFactory
    function setFeeReceiver(address feeReceiver) external onlyOwner {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();
        l.feeReceiver = feeReceiver;
        emit SetFeeReceiver(feeReceiver);
    }

    /// @inheritdoc IPoolFactory
    function deployPool(
        PoolKey memory k
    ) external payable returns (address poolAddress) {
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
        uint256 fee = initializationFee(k);

        if (_isPoolDeployed(poolKey)) revert PoolFactory__PoolAlreadyDeployed();
        if (msg.value < fee) revert PoolFactory__InitializationFeeRequired();

        payable(PoolFactoryStorage.layout().feeReceiver).transfer(fee);

        if (msg.value > fee) {
            payable(msg.sender).transfer(msg.value - fee);
        }

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
    function removeDiscount(PoolKey memory k) external {
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

        uint256 spot = getSpotPrice(baseOracle, quoteOracle);
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

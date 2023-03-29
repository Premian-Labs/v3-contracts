// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";
import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO, ONE} from "../libraries/Constants.sol";

contract PoolFactory is IPoolFactory, SafeOwnable {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolFactoryStorage for PoolKey;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable DIAMOND;
    // Chainlink price oracle for the WrappedNative/USD pair
    address internal immutable CHAINLINK_ADAPTER;
    // Wrapped native token address (eg WETH, WFTM, etc)
    address internal immutable WRAPPED_NATIVE_TOKEN;

    constructor(
        address diamond,
        address chainlinkAdapter,
        address wrappedNativeToken
    ) {
        DIAMOND = diamond;
        CHAINLINK_ADAPTER = chainlinkAdapter;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
    }

    /// @inheritdoc IPoolFactory
    function isPool(address contractAddress) external view returns (bool) {
        return PoolFactoryStorage.layout().isPool[contractAddress];
    }

    /// @inheritdoc IPoolFactory
    function getPoolAddress(PoolKey memory k) external view returns (address) {
        return _getPoolAddress(k.poolKey());
    }

    function _getPoolAddress(bytes32 poolKey) internal view returns (address) {
        return PoolFactoryStorage.layout().pools[poolKey];
    }

    // @inheritdoc IPoolFactory
    function initializationFee(PoolKey memory k) public view returns (UD60x18) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        uint256 discountFactor = l.maturityCount[k.maturityKey()] +
            l.strikeCount[k.strikeKey()];

        UD60x18 discount = (ONE - l.discountPerPool)
            .intoSD59x18()
            .powu(discountFactor)
            .intoUD60x18();

        UD60x18 spot = _fetchQuote(k.oracleAdapter, k.base, k.quote);
        UD60x18 fee = OptionMath.initializationFee(spot, k.strike, k.maturity);
        UD60x18 wrappedNativeUSDPrice = _fetchWrappedNativeUSDQuote();

        return (fee * discount) / wrappedNativeUSDPrice;
    }

    /// @inheritdoc IPoolFactory
    function setDiscountPerPool(UD60x18 discountPerPool) external onlyOwner {
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
        if (k.base == k.quote) revert PoolFactory__IdenticalAddresses();

        if (
            k.base == address(0) ||
            k.quote == address(0) ||
            k.oracleAdapter == address(0)
        ) revert PoolFactory__ZeroAddress();

        IOracleAdapter(k.oracleAdapter).upsertPair(k.base, k.quote);

        _ensureOptionStrikeIsValid(k.strike, k.oracleAdapter, k.base, k.quote);
        _ensureOptionMaturityIsValid(k.maturity);

        bytes32 poolKey = k.poolKey();
        uint256 fee = initializationFee(k).unwrap();

        if (_getPoolAddress(poolKey) != address(0))
            revert PoolFactory__PoolAlreadyDeployed();

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
                k.oracleAdapter,
                k.strike,
                k.maturity,
                k.isCallPool
            )
        );

        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();
        l.pools[poolKey] = poolAddress;
        l.isPool[poolAddress] = true;
        l.strikeCount[k.strikeKey()] += 1;
        l.maturityCount[k.maturityKey()] += 1;

        emit PoolDeployed(
            k.base,
            k.quote,
            k.oracleAdapter,
            k.strike,
            k.maturity,
            k.isCallPool,
            poolAddress
        );

        {
            (
                IOracleAdapter.AdapterType baseAdapterType,
                address[][] memory basePath,
                uint8[] memory basePathDecimals
            ) = IOracleAdapter(k.oracleAdapter).describePricingPath(k.base);

            (
                IOracleAdapter.AdapterType quoteAdapterType,
                address[][] memory quotePath,
                uint8[] memory quotePathDecimals
            ) = IOracleAdapter(k.oracleAdapter).describePricingPath(k.quote);

            emit PricingPath(
                poolAddress,
                basePath,
                basePathDecimals,
                baseAdapterType,
                quotePath,
                quotePathDecimals,
                quoteAdapterType
            );
        }
    }

    /// @inheritdoc IPoolFactory
    function removeDiscount(PoolKey memory k) external {
        if (block.timestamp < k.maturity) revert PoolFactory__PoolNotExpired();

        if (PoolFactoryStorage.layout().pools[k.poolKey()] != msg.sender)
            revert PoolFactory__NotAuthorized();

        PoolFactoryStorage.layout().strikeCount[k.strikeKey()] -= 1;
        PoolFactoryStorage.layout().maturityCount[k.maturityKey()] -= 1;
    }

    // @notice We use the given oracle adapter to fetch the price of the base/quote pair.
    //         This is used in the calculation of the initializationFee and to check the strike increment
    function _fetchQuote(
        address oracleAdapter,
        address base,
        address quote
    ) internal view returns (UD60x18) {
        return IOracleAdapter(oracleAdapter).quote(base, quote);
    }

    // @notice We use the Premia Chainlink Adapter to fetch the price of the wrapped native token.
    //         This is used to convert the initializationFee from USD to native token
    function _fetchWrappedNativeUSDQuote() internal view returns (UD60x18) {
        return
            IOracleAdapter(CHAINLINK_ADAPTER).quote(
                WRAPPED_NATIVE_TOKEN,
                Denominations.USD
            );
    }

    /// @notice Ensure that the strike price is a multiple of the strike interval, revert otherwise
    function _ensureOptionStrikeIsValid(
        UD60x18 strike,
        address oracleAdapter,
        address base,
        address quote
    ) internal view {
        if (strike == ZERO) revert PoolFactory__OptionStrikeEqualsZero();

        UD60x18 spot = _fetchQuote(oracleAdapter, base, quote);
        UD60x18 strikeInterval = OptionMath.calculateStrikeInterval(spot);

        if (strike % strikeInterval != ZERO)
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

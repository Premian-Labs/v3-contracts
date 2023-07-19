// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IPoolFactory} from "./IPoolFactory.sol";
import {IPoolFactoryDeployer} from "./IPoolFactoryDeployer.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";
import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO, ONE} from "../libraries/Constants.sol";

contract PoolFactory is IPoolFactory, OwnableInternal, ReentrancyGuard {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolFactoryStorage for PoolKey;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable DIAMOND;
    // Chainlink price oracle for the WrappedNative/USD pair
    address internal immutable CHAINLINK_ADAPTER;
    // Wrapped native token address (eg WETH, WFTM, etc)
    address internal immutable WRAPPED_NATIVE_TOKEN;
    // Address of the contract handling the proxy deployment.
    // This is in a separate contract so that we can upgrade this contract without having deterministic address calculation change
    address internal immutable POOL_FACTORY_DEPLOYER;

    constructor(address diamond, address chainlinkAdapter, address wrappedNativeToken, address poolFactoryDeployer) {
        DIAMOND = diamond;
        CHAINLINK_ADAPTER = chainlinkAdapter;
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        POOL_FACTORY_DEPLOYER = poolFactoryDeployer;
    }

    /// @inheritdoc IPoolFactory
    function isPool(address contractAddress) external view returns (bool) {
        return PoolFactoryStorage.layout().isPool[contractAddress];
    }

    /// @inheritdoc IPoolFactory
    function getPoolAddress(PoolKey calldata k) external view returns (address pool, bool isDeployed) {
        pool = _getPoolAddress(k.poolKey());
        isDeployed = true;

        if (pool == address(0)) {
            _revertIfAddressInvalid(k);
            _revertIfOptionStrikeInvalid(k.strike);
            _revertIfOptionMaturityInvalid(k.maturity);

            pool = IPoolFactoryDeployer(POOL_FACTORY_DEPLOYER).calculatePoolAddress(k);
            isDeployed = false;
        }
    }

    /// @notice Returns the address of a pool using the encoded `poolKey`
    function _getPoolAddress(bytes32 poolKey) internal view returns (address) {
        return PoolFactoryStorage.layout().pools[poolKey];
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
    function deployPool(PoolKey calldata k) external payable nonReentrant returns (address poolAddress) {
        _revertIfAddressInvalid(k);

        IOracleAdapter(k.oracleAdapter).upsertPair(k.base, k.quote);

        _revertIfOptionStrikeInvalid(k.strike);
        _revertIfOptionMaturityInvalid(k.maturity);

        bytes32 poolKey = k.poolKey();
        uint256 fee = initializationFee(k).unwrap();

        if (fee == 0) revert PoolFactory__InitializationFeeIsZero();
        if (msg.value < fee) revert PoolFactory__InitializationFeeRequired(msg.value, fee);

        address _poolAddress = _getPoolAddress(poolKey);
        if (_poolAddress != address(0)) revert PoolFactory__PoolAlreadyDeployed(_poolAddress);

        _safeTransferNativeToken(PoolFactoryStorage.layout().feeReceiver, fee);
        if (msg.value > fee) _safeTransferNativeToken(msg.sender, msg.value - fee);

        poolAddress = IPoolFactoryDeployer(POOL_FACTORY_DEPLOYER).deployPool(k);

        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();
        l.pools[poolKey] = poolAddress;
        l.isPool[poolAddress] = true;
        l.strikeCount[k.strikeKey()] += 1;
        l.maturityCount[k.maturityKey()] += 1;

        emit PoolDeployed(k.base, k.quote, k.oracleAdapter, k.strike, k.maturity, k.isCallPool, poolAddress);

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
    function removeDiscount(PoolKey calldata k) external nonReentrant {
        if (block.timestamp < k.maturity) revert PoolFactory__PoolNotExpired();

        if (PoolFactoryStorage.layout().pools[k.poolKey()] != msg.sender) revert PoolFactory__NotAuthorized();

        PoolFactoryStorage.layout().strikeCount[k.strikeKey()] -= 1;
        PoolFactoryStorage.layout().maturityCount[k.maturityKey()] -= 1;
    }

    /// @inheritdoc IPoolFactory
    function initializationFee(IPoolFactory.PoolKey calldata k) public view returns (UD60x18) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        uint256 discountFactor = l.maturityCount[k.maturityKey()] + l.strikeCount[k.strikeKey()];
        UD60x18 discount = (ONE - l.discountPerPool).intoSD59x18().powu(discountFactor).intoUD60x18();

        UD60x18 spot = _getSpotPrice(k.oracleAdapter, k.base, k.quote);
        UD60x18 fee = OptionMath.initializationFee(spot, k.strike, k.maturity);

        return (fee * discount) / _getWrappedNativeUSDSpotPrice();
    }

    /// @notice We use the given oracle adapter to fetch the spot price of the base/quote pair.
    ///         This is used in the calculation of the initializationFee
    function _getSpotPrice(address oracleAdapter, address base, address quote) internal view returns (UD60x18) {
        return IOracleAdapter(oracleAdapter).getPrice(base, quote);
    }

    /// @notice We use the Premia Chainlink Adapter to fetch the spot price of the wrapped native token in USD.
    ///         This is used to convert the initializationFee from USD to native token
    function _getWrappedNativeUSDSpotPrice() internal view returns (UD60x18) {
        return IOracleAdapter(CHAINLINK_ADAPTER).getPrice(WRAPPED_NATIVE_TOKEN, Denominations.USD);
    }

    /// @notice Safely transfer native token to the given address
    function _safeTransferNativeToken(address to, uint256 amount) internal {
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert PoolFactory__TransferNativeTokenFailed();
    }

    /// @notice Revert if the base and quote are identical or if the base, quote, or oracle adapter are zero
    function _revertIfAddressInvalid(PoolKey calldata k) internal pure {
        if (k.base == k.quote) revert PoolFactory__IdenticalAddresses();
        if (k.base == address(0) || k.quote == address(0) || k.oracleAdapter == address(0))
            revert PoolFactory__ZeroAddress();
    }

    /// @notice Revert if the strike price is not a multiple of the strike interval
    function _revertIfOptionStrikeInvalid(UD60x18 strike) internal pure {
        if (strike == ZERO) revert PoolFactory__OptionStrikeEqualsZero();
        UD60x18 strikeInterval = OptionMath.calculateStrikeInterval(strike);
        if (strike % strikeInterval != ZERO) revert PoolFactory__OptionStrikeInvalid(strike, strikeInterval);
    }

    /// @notice Revert if the maturity is invalid
    function _revertIfOptionMaturityInvalid(uint256 maturity) internal view {
        if (maturity <= block.timestamp) revert PoolFactory__OptionExpired(maturity);
        if (!OptionMath.is8AMUTC(maturity)) revert PoolFactory__OptionMaturityNot8UTC(maturity);

        uint256 ttm = OptionMath.calculateTimeToMaturity(maturity);

        if (ttm >= 3 days && ttm <= 30 days) {
            if (!OptionMath.isFriday(maturity)) revert PoolFactory__OptionMaturityNotFriday(maturity);
        }

        if (ttm > 30 days) {
            if (!OptionMath.isLastFriday(maturity)) revert PoolFactory__OptionMaturityNotLastFriday(maturity);
        }

        if (ttm > 365 days) revert PoolFactory__OptionMaturityExceedsMax(maturity);
    }
}

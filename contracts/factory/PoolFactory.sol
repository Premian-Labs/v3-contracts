// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IInitFeeCalculator} from "./IInitFeeCalculator.sol";
import {IPoolFactory} from "./IPoolFactory.sol";
import {PoolFactoryStorage} from "./PoolFactoryStorage.sol";
import {PoolProxy, PoolStorage} from "../pool/PoolProxy.sol";
import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";

import {OptionMath} from "../libraries/OptionMath.sol";
import {ZERO} from "../libraries/Constants.sol";

contract PoolFactory is IPoolFactory, OwnableInternal {
    using PoolFactoryStorage for PoolFactoryStorage.Layout;
    using PoolFactoryStorage for PoolKey;
    using PoolStorage for PoolStorage.Layout;

    address internal immutable DIAMOND;
    // Chainlink price oracle for the WrappedNative/USD pair
    address internal immutable CHAINLINK_ADAPTER;
    // Contract handling the calculation of initialization fee
    address internal immutable INIT_FEE_CALCULATOR;

    constructor(address diamond, address chainlinkAdapter, address initFeeCalculator) {
        DIAMOND = diamond;
        CHAINLINK_ADAPTER = chainlinkAdapter;
        INIT_FEE_CALCULATOR = initFeeCalculator;
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
            _revertIfOptionStrikeInvalid(k.strike, k.oracleAdapter, k.base, k.quote);
            _revertIfOptionMaturityInvalid(k.maturity);

            pool = _calculatePoolAddress(k);
            isDeployed = false;
        }
    }

    /// @notice Returns the address of a pool using the encoded `poolKey`
    function _getPoolAddress(bytes32 poolKey) internal view returns (address) {
        return PoolFactoryStorage.layout().pools[poolKey];
    }

    // @inheritdoc IPoolFactory
    function initializationFee(PoolKey calldata k) public view returns (UD60x18) {
        PoolFactoryStorage.Layout storage l = PoolFactoryStorage.layout();

        return
            IInitFeeCalculator(INIT_FEE_CALCULATOR).initializationFee(
                k,
                l.discountPerPool,
                l.maturityCount[k.maturityKey()],
                l.strikeCount[k.strikeKey()]
            );
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
    function deployPool(PoolKey calldata k) external payable returns (address poolAddress) {
        _revertIfAddressInvalid(k);

        IOracleAdapter(k.oracleAdapter).upsertPair(k.base, k.quote);

        _revertIfOptionStrikeInvalid(k.strike, k.oracleAdapter, k.base, k.quote);
        _revertIfOptionMaturityInvalid(k.maturity);

        bytes32 poolKey = k.poolKey();
        uint256 fee = initializationFee(k).unwrap();

        address _poolAddress = _getPoolAddress(poolKey);
        if (_poolAddress != address(0)) revert PoolFactory__PoolAlreadyDeployed(_poolAddress);

        if (fee > 0) {
            if (msg.value < fee) revert PoolFactory__InitializationFeeRequired(msg.value, fee);

            payable(PoolFactoryStorage.layout().feeReceiver).transfer(fee);

            if (msg.value > fee) {
                payable(msg.sender).transfer(msg.value - fee);
            }
        }

        bytes32 salt = keccak256(_encodePoolProxyArgs(k));

        poolAddress = address(
            new PoolProxy{salt: salt}(DIAMOND, k.base, k.quote, k.oracleAdapter, k.strike, k.maturity, k.isCallPool)
        );

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
    function removeDiscount(PoolKey calldata k) external {
        if (block.timestamp < k.maturity) revert PoolFactory__PoolNotExpired();

        if (PoolFactoryStorage.layout().pools[k.poolKey()] != msg.sender) revert PoolFactory__NotAuthorized();

        PoolFactoryStorage.layout().strikeCount[k.strikeKey()] -= 1;
        PoolFactoryStorage.layout().maturityCount[k.maturityKey()] -= 1;
    }

    /// @notice Returns the encoded arguments for the pool proxy using pool key `k`
    function _encodePoolProxyArgs(PoolKey memory k) internal view returns (bytes memory) {
        return abi.encode(DIAMOND, k.base, k.quote, k.oracleAdapter, k.strike, k.maturity, k.isCallPool);
    }

    /// @notice Calculates the pool address using the pool key `k`
    function _calculatePoolAddress(PoolKey memory k) internal view returns (address) {
        bytes memory args = _encodePoolProxyArgs(k);

        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff), // 0
                address(this), // address of factory contract
                keccak256(args), // salt
                // The contract bytecode
                keccak256(abi.encodePacked(type(PoolProxy).creationCode, args))
            )
        );

        // Cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    /// @notice Revert if the base and quote are identical or if the base, quote, or oracle adapter are zero
    function _revertIfAddressInvalid(PoolKey memory k) internal pure {
        if (k.base == k.quote) revert PoolFactory__IdenticalAddresses();
        if (k.base == address(0) || k.quote == address(0) || k.oracleAdapter == address(0))
            revert PoolFactory__ZeroAddress();
    }

    /// @notice Revert if the strike price is not a multiple of the strike interval
    function _revertIfOptionStrikeInvalid(
        UD60x18 strike,
        address oracleAdapter,
        address base,
        address quote
    ) internal view {
        if (strike == ZERO) revert PoolFactory__OptionStrikeEqualsZero();
        UD60x18 spot = IOracleAdapter(oracleAdapter).getPrice(base, quote);
        UD60x18 strikeInterval = OptionMath.calculateStrikeInterval(spot);
        if (strike % strikeInterval != ZERO) revert PoolFactory__OptionStrikeInvalid(strike, strikeInterval);
    }

    /// @notice Revert if the maturity is invalid
    function _revertIfOptionMaturityInvalid(uint256 maturity) internal view {
        if (maturity <= block.timestamp) revert PoolFactory__OptionExpired(maturity);
        if ((maturity % 24 hours) % 8 hours != 0) revert PoolFactory__OptionMaturityNot8UTC(maturity);

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

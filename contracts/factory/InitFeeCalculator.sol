// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOracleAdapter} from "../adapter/IOracleAdapter.sol";
import {ONE} from "../libraries/Constants.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

import {IInitFeeCalculator} from "./IInitFeeCalculator.sol";
import {IPoolFactory} from "./IPoolFactory.sol";

/// @notice Contract handling the calculation of initialization fee.
///         This is a separate contract, so that it can be upgraded without having to upgrade the PoolFactory (there is
///         some extra complexity in upgrading PoolFactory because of the fact in uses deterministic pool deployment)
contract InitFeeCalculator is IInitFeeCalculator {
    // Wrapped native token address (eg WETH, WFTM, etc)
    address internal immutable WRAPPED_NATIVE_TOKEN;
    // Chainlink price oracle for the WrappedNative/USD pair
    address internal immutable CHAINLINK_ADAPTER;

    constructor(address wrappedNativeToken, address chainlinkAdapter) {
        WRAPPED_NATIVE_TOKEN = wrappedNativeToken;
        CHAINLINK_ADAPTER = chainlinkAdapter;
    }

    // @inheritdoc IInitFeeCalculator
    function initializationFee(
        IPoolFactory.PoolKey memory k,
        UD60x18 discountPerPool,
        uint256 maturityCount,
        uint256 strikeCount
    ) external view returns (UD60x18) {
        uint256 discountFactor = maturityCount + strikeCount;

        UD60x18 discount = (ONE - discountPerPool).intoSD59x18().powu(discountFactor).intoUD60x18();

        UD60x18 spot = _getSpotPrice(k.oracleAdapter, k.base, k.quote);
        UD60x18 fee = OptionMath.initializationFee(spot, k.strike, k.maturity);

        return (fee * discount) / _getWrappedNativeUSDSpotPrice();
    }

    // @notice We use the given oracle adapter to fetch the spot price of the base/quote pair.
    //         This is used in the calculation of the initializationFee
    function _getSpotPrice(address oracleAdapter, address base, address quote) internal view returns (UD60x18) {
        return IOracleAdapter(oracleAdapter).quote(base, quote);
    }

    // @notice We use the Premia Chainlink Adapter to fetch the spot price of the wrapped native token in USD.
    //         This is used to convert the initializationFee from USD to native token
    function _getWrappedNativeUSDSpotPrice() internal view returns (UD60x18) {
        return IOracleAdapter(CHAINLINK_ADAPTER).quote(WRAPPED_NATIVE_TOKEN, Denominations.USD);
    }
}

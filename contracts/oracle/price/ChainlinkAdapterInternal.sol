// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/src/UD60x18.sol";

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {IAggregator} from "./IAggregator.sol";
import {IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";
import {ChainlinkAdapterStorage} from "./ChainlinkAdapterStorage.sol";
import {OracleAdapterInternal} from "./OracleAdapterInternal.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract ChainlinkAdapterInternal is
    IChainlinkAdapterInternal,
    OracleAdapterInternal
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;
    using SafeCast for int256;

    /// @dev If a fresh price is unavailable the adapter will wait the duration of
    ///      MAX_DELAY before returning the stale price
    uint32 internal constant MAX_DELAY = 12 hours;
    /// @dev If the difference between target and last update is greater than the
    ///      PRICE_STALE_THRESHOLD, the price is considered stale
    uint32 internal constant PRICE_STALE_THRESHOLD = 25 hours;

    int256 private constant FOREX_DECIMALS = 8;

    uint256 private constant ONE_USD = 10 ** uint256(FOREX_DECIMALS);
    uint256 private constant ONE_BTC = 10 ** uint256(FOREX_DECIMALS);

    address internal immutable WRAPPED_NATIVE_TOKEN;
    address internal immutable WRAPPED_BTC_TOKEN;

    constructor(address _wrappedNativeToken, address _wrappedBTCToken) {
        WRAPPED_NATIVE_TOKEN = _wrappedNativeToken;
        WRAPPED_BTC_TOKEN = _wrappedBTCToken;
    }

    function _quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        (
            PricingPath path,
            address mappedTokenIn,
            address mappedTokenOut
        ) = _pathForPair(tokenIn, tokenOut, false);

        if (path == PricingPath.NONE) {
            path = _determinePricingPath(mappedTokenIn, mappedTokenOut);

            if (path == PricingPath.NONE)
                revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);
        }
        if (path <= PricingPath.TOKEN_ETH) {
            return _getDirectPrice(path, mappedTokenIn, mappedTokenOut, target);
        } else if (path <= PricingPath.TOKEN_ETH_TOKEN) {
            return
                _getPriceSameBase(path, mappedTokenIn, mappedTokenOut, target);
        } else if (path <= PricingPath.A_ETH_USD_B) {
            return
                _getPriceDifferentBases(
                    path,
                    mappedTokenIn,
                    mappedTokenOut,
                    target
                );
        } else {
            return
                _getPriceWBTCPrice(path, mappedTokenIn, mappedTokenOut, target);
        }
    }

    function _pathForPair(
        address tokenA,
        address tokenB,
        bool sortTokens
    )
        internal
        view
        returns (PricingPath path, address mappedTokenA, address mappedTokenB)
    {
        (mappedTokenA, mappedTokenB) = _mapToDenomination(tokenA, tokenB);

        (address sortedA, address sortedB) = _sortTokens(
            mappedTokenA,
            mappedTokenB
        );

        path = ChainlinkAdapterStorage.layout().pathForPair[
            _keyForSortedPair(sortedA, sortedB)
        ];

        if (sortTokens) {
            mappedTokenA = sortedA;
            mappedTokenB = sortedB;
        }
    }

    /// @dev Handles prices when the pair is either ETH/USD, token/ETH or token/USD
    function _getDirectPrice(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        int256 factor = _factor(path);

        uint256 price;
        if (path == PricingPath.ETH_USD) {
            price = _getETHUSD(target);
        } else if (path == PricingPath.TOKEN_USD) {
            price = _getPriceAgainstUSD(
                _isUSD(tokenOut) ? tokenIn : tokenOut,
                target
            );
        } else if (path == PricingPath.TOKEN_ETH) {
            price = _getPriceAgainstETH(
                _isETH(tokenOut) ? tokenIn : tokenOut,
                target
            ).unwrap();
        }

        UD60x18 priceScaled = UD60x18.wrap(_scale(price, factor));

        bool invert = _isUSD(tokenIn) ||
            (path == PricingPath.TOKEN_ETH && _isETH(tokenIn));

        return invert ? priceScaled.inv() : priceScaled;
    }

    /// @dev Handles prices when both tokens share the same base (either ETH or USD)
    function _getPriceSameBase(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        int256 factor = _factor(path);

        address base = path == PricingPath.TOKEN_USD_TOKEN
            ? Denominations.USD
            : Denominations.ETH;

        uint256 tokenInToBase = _fetchQuote(tokenIn, base, target);
        uint256 tokenOutToBase = _fetchQuote(tokenOut, base, target);

        UD60x18 adjustedTokenInToBase = UD60x18.wrap(
            _scale(tokenInToBase, factor)
        );
        UD60x18 adjustedTokenOutToBase = UD60x18.wrap(
            _scale(tokenOutToBase, factor)
        );

        return adjustedTokenInToBase / adjustedTokenOutToBase;
    }

    /// @dev Handles prices when one of the tokens uses ETH as the base, and the other USD
    function _getPriceDifferentBases(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        int256 factor = _factor(path);
        UD60x18 adjustedEthToUSDPrice = UD60x18.wrap(
            _scale(_getETHUSD(target), factor)
        );

        bool isTokenInUSD = (path == PricingPath.A_USD_ETH_B &&
            tokenIn < tokenOut) ||
            (path == PricingPath.A_ETH_USD_B && tokenIn > tokenOut);

        if (isTokenInUSD) {
            UD60x18 adjustedTokenInToUSD = UD60x18.wrap(
                _scale(_getPriceAgainstUSD(tokenIn, target), factor)
            );

            UD60x18 tokenOutToETH = _getPriceAgainstETH(tokenOut, target);

            return adjustedTokenInToUSD / adjustedEthToUSDPrice / tokenOutToETH;
        } else {
            UD60x18 tokenInToETH = _getPriceAgainstETH(tokenIn, target);

            UD60x18 adjustedTokenOutToUSD = UD60x18.wrap(
                _scale(_getPriceAgainstUSD(tokenOut, target), factor)
            );

            return
                (tokenInToETH * adjustedEthToUSDPrice) / adjustedTokenOutToUSD;
        }
    }

    /// @dev Handles prices when the pair is token/WBTC
    function _getPriceWBTCPrice(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        int256 factor = _factor(path);
        bool isTokenInWBTC = _isWBTC(tokenIn);

        UD60x18 adjustedWBTCToUSDPrice = UD60x18.wrap(
            _scale(_getWBTCBTC(target), factor)
        ) * UD60x18.wrap(_scale(_getBTCUSD(target), factor));

        UD60x18 adjustedTokenToUSD = UD60x18.wrap(
            _scale(
                _getPriceAgainstUSD(
                    !isTokenInWBTC ? tokenIn : tokenOut,
                    target
                ),
                factor
            )
        );

        UD60x18 price = adjustedWBTCToUSDPrice / adjustedTokenToUSD;
        return !isTokenInWBTC ? price.inv() : price;
    }

    function _factor(PricingPath path) internal pure returns (int256) {
        if (
            path == PricingPath.ETH_USD ||
            path == PricingPath.TOKEN_USD ||
            path == PricingPath.TOKEN_USD_TOKEN ||
            path == PricingPath.A_USD_ETH_B ||
            path == PricingPath.A_ETH_USD_B ||
            path == PricingPath.TOKEN_USD_BTC_WBTC
        ) {
            return ETH_DECIMALS - FOREX_DECIMALS;
        }

        return 0;
    }

    function _getPriceAgainstUSD(
        address token,
        uint256 target
    ) internal view returns (uint256) {
        return
            _isUSD(token)
                ? ONE_USD
                : _fetchQuote(token, Denominations.USD, target);
    }

    function _getPriceAgainstETH(
        address token,
        uint256 target
    ) internal view returns (UD60x18) {
        return
            UD60x18.wrap(
                _isETH(token)
                    ? ONE_ETH
                    : _fetchQuote(token, Denominations.ETH, target)
            );
    }

    /// @dev Expects `tokenA` and `tokenB` to be sorted
    function _determinePricingPath(
        address tokenA,
        address tokenB
    ) internal view virtual returns (PricingPath) {
        if (tokenA == tokenB)
            revert OracleAdapter__TokensAreSame(tokenA, tokenB);

        bool isTokenAUSD = _isUSD(tokenA);
        bool isTokenBUSD = _isUSD(tokenB);
        bool isTokenAETH = _isETH(tokenA);
        bool isTokenBETH = _isETH(tokenB);
        bool isTokenAWBTC = _isWBTC(tokenA);
        bool isTokenBWBTC = _isWBTC(tokenB);

        if ((isTokenAETH && isTokenBUSD) || (isTokenAUSD && isTokenBETH)) {
            return PricingPath.ETH_USD;
        }

        address srcToken;
        ConversionType conversionType;
        PricingPath preferredPath;
        PricingPath fallbackPath;

        bool wbtcUSDFeedExists = _exists(
            isTokenAWBTC ? tokenA : tokenB,
            Denominations.USD
        );

        if ((isTokenAWBTC || isTokenBWBTC) && !wbtcUSDFeedExists) {
            // If one of the token is WBTC and there is no WBTC/USD feed, we want to convert the other token to WBTC
            // Note: If there is a WBTC/USD feed the preferred path is TOKEN_USD, TOKEN_USD_TOKEN, or A_USD_ETH_B
            srcToken = isTokenAWBTC ? tokenB : tokenA;
            conversionType = ConversionType.ToBtc;
            // PricingPath used are same, but effective path slightly differs because of the 2 attempts in `_tryToFindPath`
            preferredPath = PricingPath.TOKEN_USD_BTC_WBTC; // Token -> USD -> BTC -> WBTC
            fallbackPath = PricingPath.TOKEN_USD_BTC_WBTC; // Token -> BTC -> WBTC
        } else if (isTokenBUSD) {
            // If tokenB is USD, we want to convert tokenA to USD
            srcToken = tokenA;
            conversionType = ConversionType.ToUsd;
            preferredPath = PricingPath.TOKEN_USD;
            fallbackPath = PricingPath.A_ETH_USD_B; // USD -> B is skipped, if B == USD
        } else if (isTokenAUSD) {
            // If tokenA is USD, we want to convert tokenB to USD
            srcToken = tokenB;
            conversionType = ConversionType.ToUsd;
            preferredPath = PricingPath.TOKEN_USD;
            fallbackPath = PricingPath.A_USD_ETH_B; // A -> USD is skipped, if A == USD
        } else if (isTokenBETH) {
            // If tokenB is ETH, we want to convert tokenA to ETH
            srcToken = tokenA;
            conversionType = ConversionType.ToEth;
            preferredPath = PricingPath.TOKEN_ETH;
            fallbackPath = PricingPath.A_USD_ETH_B; // B -> ETH is skipped, if B == ETH
        } else if (isTokenAETH) {
            // If tokenA is ETH, we want to convert tokenB to ETH
            srcToken = tokenB;
            conversionType = ConversionType.ToEth;
            preferredPath = PricingPath.TOKEN_ETH;
            fallbackPath = PricingPath.A_ETH_USD_B; // A -> ETH is skipped, if A == ETH
        } else if (_exists(tokenA, Denominations.USD)) {
            // If tokenA has a USD feed, we want to convert tokenB to USD, and then use tokenA USD feed to effectively convert tokenB -> tokenA
            srcToken = tokenB;
            conversionType = ConversionType.ToUsdToToken;
            preferredPath = PricingPath.TOKEN_USD_TOKEN;
            fallbackPath = PricingPath.A_USD_ETH_B;
        } else if (_exists(tokenA, Denominations.ETH)) {
            // If tokenA has an ETH feed, we want to convert tokenB to ETH, and then use tokenA ETH feed to effectively convert tokenB -> tokenA
            srcToken = tokenB;
            conversionType = ConversionType.ToEthToToken;
            preferredPath = PricingPath.TOKEN_ETH_TOKEN;
            fallbackPath = PricingPath.A_ETH_USD_B;
        } else {
            return PricingPath.NONE;
        }

        return
            _tryToFindPath(
                srcToken,
                conversionType,
                preferredPath,
                fallbackPath
            );
    }

    function _tryToFindPath(
        address token,
        ConversionType conversionType,
        PricingPath preferredPath,
        PricingPath fallbackPath
    ) internal view returns (PricingPath) {
        address firstQuote;
        address secondQuote;

        if (conversionType == ConversionType.ToBtc) {
            firstQuote = Denominations.USD;
            secondQuote = Denominations.BTC;
        } else if (conversionType == ConversionType.ToUsd) {
            firstQuote = Denominations.USD;
            secondQuote = Denominations.ETH;
        } else if (conversionType == ConversionType.ToEth) {
            firstQuote = Denominations.ETH;
            secondQuote = Denominations.USD;
        } else if (conversionType == ConversionType.ToUsdToToken) {
            firstQuote = Denominations.USD;
            secondQuote = Denominations.ETH;
        } else if (conversionType == ConversionType.ToEthToToken) {
            firstQuote = Denominations.ETH;
            secondQuote = Denominations.USD;
        }

        if (_exists(token, firstQuote)) {
            return preferredPath;
        } else if (_exists(token, secondQuote)) {
            return fallbackPath;
        } else {
            return PricingPath.NONE;
        }
    }

    function _exists(address base, address quote) internal view returns (bool) {
        return _feed(base, quote) != address(0);
    }

    function _fetchQuote(
        address base,
        address quote,
        uint256 target
    ) internal view returns (uint256) {
        return
            target == 0
                ? _fetchLatestQuote(base, quote)
                : _fetchQuoteFrom(base, quote, target);
    }

    function _fetchLatestQuote(
        address base,
        address quote
    ) internal view returns (uint256) {
        address feed = _feed(base, quote);
        (, int256 price, , , ) = _latestRoundData(feed);
        _ensurePricePositive(price);
        return price.toUint256();
    }

    function _fetchQuoteFrom(
        address base,
        address quote,
        uint256 target
    ) internal view returns (uint256) {
        address feed = _feed(base, quote);

        (
            uint80 roundId,
            int256 price,
            ,
            uint256 updatedAt,

        ) = _latestRoundData(feed);

        (uint16 phaseId, uint64 aggregatorRoundId) = ChainlinkAdapterStorage
            .parseRoundId(roundId);

        int256 previousPrice = price;
        uint256 previousUpdatedAt = updatedAt;

        // if the last observation is after the target skip loop
        if (target >= updatedAt) aggregatorRoundId = 0;

        while (aggregatorRoundId > 0) {
            roundId = ChainlinkAdapterStorage.formatRoundId(
                phaseId,
                --aggregatorRoundId
            );

            (, price, , updatedAt, ) = _getRoundData(feed, roundId);

            if (target >= updatedAt) {
                uint256 previousUpdateDistance = previousUpdatedAt - target;
                uint256 currentUpdateDistance = target - updatedAt;

                if (previousUpdateDistance < currentUpdateDistance) {
                    price = previousPrice;
                    updatedAt = previousUpdatedAt;
                }

                break;
            }

            previousPrice = price;
            previousUpdatedAt = updatedAt;
        }

        _ensurePriceAfterTargetIsFresh(target, updatedAt);
        _ensurePricePositive(price);
        return price.toUint256();
    }

    function _latestRoundData(
        address feed
    ) internal view returns (uint80, int256, uint256, uint256, uint80) {
        try IAggregator(feed).latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            return (roundId, answer, startedAt, updatedAt, answeredInRound);
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory data) {
            revert ChainlinkAdapter__LatestRoundDataCallReverted(data);
        }
    }

    function _getRoundData(
        address feed,
        uint80 roundId
    ) internal view returns (uint80, int256, uint256, uint256, uint80) {
        try IAggregator(feed).getRoundData(roundId) returns (
            uint80 _roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            return (_roundId, answer, startedAt, updatedAt, answeredInRound);
        } catch Error(string memory reason) {
            revert(reason);
        } catch (bytes memory data) {
            revert ChainlinkAdapter__GetRoundDataCallReverted(data);
        }
    }

    function _ensurePriceAfterTargetIsFresh(
        uint256 target,
        uint256 updatedAt
    ) internal view {
        if (
            target >= updatedAt &&
            block.timestamp - target < MAX_DELAY &&
            target - updatedAt >= PRICE_STALE_THRESHOLD
        ) {
            // revert if 12 hours has not passed and price is stale
            revert ChainlinkAdapter__PriceAfterTargetIsStale();
        }
    }

    function _aggregator(
        address tokenA,
        address tokenB
    ) internal view returns (address[] memory aggregator) {
        address feed = _feed(tokenA, tokenB);
        aggregator = new address[](1);
        aggregator[0] = IAggregator(feed).aggregator();
    }

    function _aggregatorDecimals(
        address aggregator
    ) internal view returns (uint8) {
        return IAggregator(aggregator).decimals();
    }

    function _feed(
        address tokenA,
        address tokenB
    ) internal view returns (address) {
        return
            ChainlinkAdapterStorage.layout().feeds[
                _keyForUnsortedPair(tokenA, tokenB)
            ];
    }

    /// @dev Should only map wrapped tokens which are guaranteed to have a 1:1 ratio
    function _tokenToDenomination(
        address token
    ) internal view returns (address) {
        return token == WRAPPED_NATIVE_TOKEN ? Denominations.ETH : token;
    }

    function _mapToDenominationAndSort(
        address tokenA,
        address tokenB
    ) internal view returns (address, address) {
        (address mappedTokenA, address mappedTokenB) = _mapToDenomination(
            tokenA,
            tokenB
        );

        return _sortTokens(mappedTokenA, mappedTokenB);
    }

    function _mapToDenomination(
        address tokenA,
        address tokenB
    ) internal view returns (address mappedTokenA, address mappedTokenB) {
        mappedTokenA = _tokenToDenomination(tokenA);
        mappedTokenB = _tokenToDenomination(tokenB);
    }

    function _getETHUSD(uint256 target) internal view returns (uint256) {
        return _fetchQuote(Denominations.ETH, Denominations.USD, target);
    }

    function _getBTCUSD(uint256 target) internal view returns (uint256) {
        return _fetchQuote(Denominations.BTC, Denominations.USD, target);
    }

    function _getWBTCBTC(uint256 target) internal view returns (uint256) {
        return _fetchQuote(WRAPPED_BTC_TOKEN, Denominations.BTC, target);
    }

    function _isUSD(address token) internal pure returns (bool) {
        return token == Denominations.USD;
    }

    function _isETH(address token) internal pure returns (bool) {
        return token == Denominations.ETH;
    }

    function _isWBTC(address token) internal view returns (bool) {
        return token == WRAPPED_BTC_TOKEN;
    }
}

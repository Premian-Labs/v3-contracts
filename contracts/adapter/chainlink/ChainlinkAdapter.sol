// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {EnumerableSet} from "@solidstate/contracts/data/EnumerableSet.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ArrayUtils} from "../../libraries/ArrayUtils.sol";
import {ZERO, ONE} from "../../libraries/Constants.sol";
import {AggregatorProxyInterface} from "../../vendor/AggregatorProxyInterface.sol";

import {FeedRegistry, IFeedRegistry} from "../FeedRegistry.sol";
import {FeedRegistryStorage} from "../FeedRegistryStorage.sol";
import {IOracleAdapter} from "../IOracleAdapter.sol";
import {OracleAdapter} from "../OracleAdapter.sol";
import {PriceRepository} from "../PriceRepository.sol";
import {ETH_DECIMALS, FOREX_DECIMALS, Tokens} from "../Tokens.sol";

import {ChainlinkAdapterStorage} from "./ChainlinkAdapterStorage.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";

/// @title An implementation of IOracleAdapter that uses Chainlink feeds
/// @notice This oracle adapter will attempt to use all available feeds to determine prices between pairs
contract ChainlinkAdapter is IChainlinkAdapter, FeedRegistry, OracleAdapter, PriceRepository {
    using ChainlinkAdapterStorage for address;
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;
    using ChainlinkAdapterStorage for IChainlinkAdapter.PricingPath;
    using EnumerableSet for EnumerableSet.AddressSet;
    using FeedRegistryStorage for FeedRegistryStorage.Layout;
    using SafeCast for int256;
    using SafeCast for uint8;
    using Tokens for address;

    /// @dev If a fresh price is unavailable the adapter will wait the duration of
    ///      MAX_DELAY before returning the stale price
    uint256 internal constant MAX_DELAY = 12 hours;
    /// @dev If the difference between target and last update is greater than the
    ///      PRICE_STALE_THRESHOLD, the price is considered stale
    uint256 internal constant PRICE_STALE_THRESHOLD = 25 hours;

    constructor(
        address _wrappedNativeToken,
        address _wrappedBTCToken
    ) FeedRegistry(_wrappedNativeToken, _wrappedBTCToken) {}

    /// @inheritdoc IOracleAdapter
    function isPairSupported(address tokenA, address tokenB) external view returns (bool isCached, bool hasPath) {
        (PricingPath path, address mappedTokenA, address mappedTokenB) = _pricingPath(tokenA, tokenB);

        isCached = path != PricingPath.NONE;
        if (isCached) return (isCached, true);

        hasPath = _determinePricingPath(mappedTokenA, mappedTokenB) != PricingPath.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function upsertPair(address tokenA, address tokenB) external nonReentrant {
        (address sortedA, address sortedB) = _mapToDenominationAndSort(tokenA, tokenB);

        PricingPath path = _determinePricingPath(sortedA, sortedB);
        bytes32 keyForPair = sortedA.keyForSortedPair(sortedB);

        ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage.layout();

        if (path == PricingPath.NONE) {
            // Check if there is a current path. If there is, it means that the pair was supported and it
            // lost support. In that case, we will remove the current path and continue working as expected.
            // If there was no supported path, and there still isn't, then we will fail
            if (l.pricingPath[keyForPair] == PricingPath.NONE)
                revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);
        }

        if (l.pricingPath[keyForPair] == path) return;
        l.pricingPath[keyForPair] = path;

        if (!l.pairedTokens[sortedA].contains(sortedB)) l.pairedTokens[sortedA].add(sortedB);
        if (!l.pairedTokens[sortedB].contains(sortedA)) l.pairedTokens[sortedB].add(sortedA);

        emit UpdatedPathForPair(sortedA, sortedB, path);
    }

    /// @inheritdoc IOracleAdapter
    function getPrice(address tokenIn, address tokenOut) external view returns (UD60x18) {
        return _getPriceAt(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    function getPriceAt(address tokenIn, address tokenOut, uint256 target) external view returns (UD60x18) {
        _revertIfTargetInvalid(target);
        return _getPriceAt(tokenIn, tokenOut, target);
    }

    /// @notice Returns a price based on the pricing path between `tokenIn` and `tokenOut`
    function _getPriceAt(address tokenIn, address tokenOut, uint256 target) internal view returns (UD60x18) {
        (PricingPath path, address mappedTokenIn, address mappedTokenOut) = _pricingPath(tokenIn, tokenOut);

        if (path == PricingPath.NONE) {
            path = _determinePricingPath(mappedTokenIn, mappedTokenOut);
            if (path == PricingPath.NONE) revert OracleAdapter__PairNotSupported(tokenIn, tokenOut);
        }
        if (path <= PricingPath.TOKEN_ETH) {
            return _getDirectPrice(path, mappedTokenIn, mappedTokenOut, target);
        } else if (path <= PricingPath.TOKEN_ETH_TOKEN) {
            return _getPriceSameBase(path, mappedTokenIn, mappedTokenOut, target);
        } else if (path <= PricingPath.A_ETH_USD_B) {
            return _getPriceDifferentBases(path, mappedTokenIn, mappedTokenOut, target);
        } else {
            return _getPriceWBTCPrice(mappedTokenIn, mappedTokenOut, target);
        }
    }

    /// @inheritdoc IOracleAdapter
    function describePricingPath(
        address token
    ) external view returns (AdapterType adapterType, address[][] memory path, uint8[] memory decimals) {
        adapterType = AdapterType.Chainlink;
        path = new address[][](2);
        decimals = new uint8[](2);

        token = _tokenToDenomination(token);

        if (token == Denominations.ETH) {
            address[] memory aggregator = new address[](1);
            aggregator[0] = Denominations.ETH;
            path[0] = aggregator;
        } else if (_feedExists(token, Denominations.ETH)) {
            path[0] = _aggregator(token, Denominations.ETH);
        } else if (_feedExists(token, Denominations.USD)) {
            path[0] = _aggregator(token, Denominations.USD);
            path[1] = _aggregator(Denominations.ETH, Denominations.USD);
        }

        if (path[0].length > 0) {
            decimals[0] = path[0][0] == Denominations.ETH ? ETH_DECIMALS : _aggregatorDecimals(path[0][0]);
        }

        if (path[1].length > 0) {
            decimals[1] = _aggregatorDecimals(path[1][0]);
        }

        if (path[0].length == 0) {
            address[][] memory temp = new address[][](0);
            path = temp;
        } else if (path[1].length == 0) {
            address[][] memory temp = new address[][](1);
            temp[0] = path[0];
            path = temp;
        }

        if (decimals[0] == 0) {
            ArrayUtils.resizeArray(decimals, 0);
        } else if (decimals[1] == 0) {
            ArrayUtils.resizeArray(decimals, 1);
        }
    }

    /// @inheritdoc IChainlinkAdapter
    function pricingPath(address tokenA, address tokenB) external view returns (PricingPath) {
        (PricingPath path, , ) = _pricingPath(tokenA, tokenB);
        return path;
    }

    function batchRegisterFeedMappings(
        FeedMappingArgs[] memory args
    ) external override(FeedRegistry, IFeedRegistry) onlyOwner {
        for (uint256 i = 0; i < args.length; i++) {
            address token = _tokenToDenomination(args[i].token);
            address denomination = args[i].denomination;
            address feed = args[i].feed;

            if (token == denomination) revert OracleAdapter__TokensAreSame(token, denomination);
            if (token == address(0) || denomination == address(0)) revert OracleAdapter__ZeroAddress();

            if (!denomination.isETH() && !denomination.isBTC() && !denomination.isUSD())
                revert ChainlinkAdapter__InvalidDenomination(denomination);

            bytes32 keyForPair = token.keyForUnsortedPair(denomination);
            FeedRegistryStorage.layout().feeds[keyForPair] = feed;

            ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage.layout();

            if (feed == address(0)) {
                for (uint256 j = 0; j < l.pairedTokens[token].length(); j++) {
                    address pairedToken = l.pairedTokens[token].at(j);
                    (address sortedA, address sortedB) = _mapToDenominationAndSort(token, pairedToken);
                    l.pricingPath[sortedA.keyForSortedPair(sortedB)] = PricingPath.NONE;
                }

                delete l.pairedTokens[token];
            }
        }

        emit FeedMappingsRegistered(args);
    }

    /// @notice Returns the pricing path between `tokenA` and `tokenB` and the mapped tokens (unsorted)
    function _pricingPath(
        address tokenA,
        address tokenB
    ) internal view returns (PricingPath path, address mappedTokenA, address mappedTokenB) {
        (mappedTokenA, mappedTokenB) = _mapToDenomination(tokenA, tokenB);
        (address sortedA, address sortedB) = mappedTokenA.sortTokens(mappedTokenB);
        path = ChainlinkAdapterStorage.layout().pricingPath[sortedA.keyForSortedPair(sortedB)];
    }

    /// @notice Returns the price of `tokenIn` denominated in `tokenOut` when the pair is either ETH/USD, token/ETH or
    ///         token/USD
    function _getDirectPrice(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        UD60x18 price;

        if (path == PricingPath.ETH_USD) {
            price = _getETHUSD(target);
        } else if (path == PricingPath.TOKEN_USD) {
            price = _getPriceAgainstUSD(tokenOut.isUSD() ? tokenIn : tokenOut, target);
        } else if (path == PricingPath.TOKEN_ETH) {
            price = _getPriceAgainstETH(tokenOut.isETH() ? tokenIn : tokenOut, target);
        }

        bool invert = tokenIn.isUSD() || (path == PricingPath.TOKEN_ETH && tokenIn.isETH());

        return invert ? price.inv() : price;
    }

    /// @notice Returns the price of `tokenIn` denominated in `tokenOut` when both tokens share the same base (either
    ///         ETH or USD)
    function _getPriceSameBase(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        int8 factor = PricingPath.TOKEN_USD_TOKEN == path ? int8(ETH_DECIMALS - FOREX_DECIMALS) : int8(0);
        address base = path == PricingPath.TOKEN_USD_TOKEN ? Denominations.USD : Denominations.ETH;

        uint256 tokenInToBase = _fetchPrice(tokenIn, base, target, factor);
        uint256 tokenOutToBase = _fetchPrice(tokenOut, base, target, factor);

        UD60x18 adjustedTokenInToBase = ud(_scale(tokenInToBase, factor));
        UD60x18 adjustedTokenOutToBase = ud(_scale(tokenOutToBase, factor));

        return adjustedTokenInToBase / adjustedTokenOutToBase;
    }

    /// @notice Returns the price of `tokenIn` denominated in `tokenOut` when one of the tokens uses ETH as the base,
    ///         and the other USD
    function _getPriceDifferentBases(
        PricingPath path,
        address tokenIn,
        address tokenOut,
        uint256 target
    ) internal view returns (UD60x18) {
        UD60x18 adjustedEthToUSDPrice = _getETHUSD(target);

        bool isTokenInUSD = (path == PricingPath.A_USD_ETH_B && tokenIn < tokenOut) ||
            (path == PricingPath.A_ETH_USD_B && tokenIn > tokenOut);

        if (isTokenInUSD) {
            UD60x18 adjustedTokenInToUSD = _getPriceAgainstUSD(tokenIn, target);
            UD60x18 tokenOutToETH = _getPriceAgainstETH(tokenOut, target);
            return adjustedTokenInToUSD / adjustedEthToUSDPrice / tokenOutToETH;
        } else {
            UD60x18 tokenInToETH = _getPriceAgainstETH(tokenIn, target);
            UD60x18 adjustedTokenOutToUSD = _getPriceAgainstUSD(tokenOut, target);
            return (tokenInToETH * adjustedEthToUSDPrice) / adjustedTokenOutToUSD;
        }
    }

    /// @notice Returns the price of `tokenIn` denominated in `tokenOut` when the pair is token/WBTC
    function _getPriceWBTCPrice(address tokenIn, address tokenOut, uint256 target) internal view returns (UD60x18) {
        bool isTokenInWBTC = tokenIn == WRAPPED_BTC_TOKEN;

        UD60x18 adjustedWBTCToUSDPrice = _getWBTCBTC(target) * _getBTCUSD(target);
        UD60x18 adjustedTokenToUSD = _getPriceAgainstUSD(!isTokenInWBTC ? tokenIn : tokenOut, target);

        UD60x18 price = adjustedWBTCToUSDPrice / adjustedTokenToUSD;
        return !isTokenInWBTC ? price.inv() : price;
    }

    /// @notice Returns the pricing path between `tokenA` and `tokenB`
    function _determinePricingPath(address tokenA, address tokenB) internal view virtual returns (PricingPath) {
        if (tokenA == tokenB) revert OracleAdapter__TokensAreSame(tokenA, tokenB);

        (tokenA, tokenB) = tokenA.sortTokens(tokenB);

        bool isTokenAUSD = tokenA.isUSD();
        bool isTokenBUSD = tokenB.isUSD();
        bool isTokenAETH = tokenA.isETH();
        bool isTokenBETH = tokenB.isETH();
        bool isTokenAWBTC = tokenA == WRAPPED_BTC_TOKEN;
        bool isTokenBWBTC = tokenB == WRAPPED_BTC_TOKEN;

        if ((isTokenAETH && isTokenBUSD) || (isTokenAUSD && isTokenBETH)) {
            return PricingPath.ETH_USD;
        }

        address srcToken;
        ConversionType conversionType;
        PricingPath preferredPath;
        PricingPath fallbackPath;

        bool wbtcUSDFeedExists = _feedExists(isTokenAWBTC ? tokenA : tokenB, Denominations.USD);

        if ((isTokenAWBTC || isTokenBWBTC) && !wbtcUSDFeedExists) {
            // If one of the token is WBTC and there is no WBTC/USD feed, we want to convert the other token to WBTC
            // Note: If there is a WBTC/USD feed the preferred path is TOKEN_USD, TOKEN_USD_TOKEN, or A_USD_ETH_B
            srcToken = isTokenAWBTC ? tokenB : tokenA;
            conversionType = ConversionType.TO_BTC;
            // PricingPath used are same, but effective path slightly differs because of the 2 attempts in
            // `_tryToFindPath`
            preferredPath = PricingPath.TOKEN_USD_BTC_WBTC; // Token -> USD -> BTC -> WBTC
            fallbackPath = PricingPath.TOKEN_USD_BTC_WBTC; // Token -> BTC -> WBTC
        } else if (isTokenBUSD) {
            // If tokenB is USD, we want to convert tokenA to USD
            srcToken = tokenA;
            conversionType = ConversionType.TO_USD;
            preferredPath = PricingPath.TOKEN_USD;
            fallbackPath = PricingPath.A_ETH_USD_B; // USD -> B is skipped, if B == USD
        } else if (isTokenAUSD) {
            // If tokenA is USD, we want to convert tokenB to USD
            srcToken = tokenB;
            conversionType = ConversionType.TO_USD;
            preferredPath = PricingPath.TOKEN_USD;
            fallbackPath = PricingPath.A_USD_ETH_B; // A -> USD is skipped, if A == USD
        } else if (isTokenBETH) {
            // If tokenB is ETH, we want to convert tokenA to ETH
            srcToken = tokenA;
            conversionType = ConversionType.TO_ETH;
            preferredPath = PricingPath.TOKEN_ETH;
            fallbackPath = PricingPath.A_USD_ETH_B; // B -> ETH is skipped, if B == ETH
        } else if (isTokenAETH) {
            // If tokenA is ETH, we want to convert tokenB to ETH
            srcToken = tokenB;
            conversionType = ConversionType.TO_ETH;
            preferredPath = PricingPath.TOKEN_ETH;
            fallbackPath = PricingPath.A_ETH_USD_B; // A -> ETH is skipped, if A == ETH
        } else if (_feedExists(tokenA, Denominations.USD)) {
            // If tokenA has a USD feed, we want to convert tokenB to USD, and then use tokenA USD feed to effectively
            // convert tokenB -> tokenA
            srcToken = tokenB;
            conversionType = ConversionType.TO_USD_TO_TOKEN;
            preferredPath = PricingPath.TOKEN_USD_TOKEN;
            fallbackPath = PricingPath.A_USD_ETH_B;
        } else if (_feedExists(tokenA, Denominations.ETH)) {
            // If tokenA has an ETH feed, we want to convert tokenB to ETH, and then use tokenA ETH feed to effectively
            // convert tokenB -> tokenA
            srcToken = tokenB;
            conversionType = ConversionType.TO_ETH_TO_TOKEN;
            preferredPath = PricingPath.TOKEN_ETH_TOKEN;
            fallbackPath = PricingPath.A_ETH_USD_B;
        } else {
            return PricingPath.NONE;
        }

        return _tryToFindPath(srcToken, conversionType, preferredPath, fallbackPath);
    }

    /// @notice Attempts to find the best pricing path for `token` based on the `conversionType`, if a feed exists
    function _tryToFindPath(
        address token,
        ConversionType conversionType,
        PricingPath preferredPath,
        PricingPath fallbackPath
    ) internal view returns (PricingPath) {
        address preferredQuote;
        address fallbackQuote;

        if (conversionType == ConversionType.TO_BTC) {
            preferredQuote = Denominations.USD;
            fallbackQuote = Denominations.BTC;
        } else if (conversionType == ConversionType.TO_USD) {
            preferredQuote = Denominations.USD;
            fallbackQuote = Denominations.ETH;
        } else if (conversionType == ConversionType.TO_ETH) {
            preferredQuote = Denominations.ETH;
            fallbackQuote = Denominations.USD;
        } else if (conversionType == ConversionType.TO_USD_TO_TOKEN) {
            preferredQuote = Denominations.USD;
            fallbackQuote = Denominations.ETH;
        } else if (conversionType == ConversionType.TO_ETH_TO_TOKEN) {
            preferredQuote = Denominations.ETH;
            fallbackQuote = Denominations.USD;
        }

        if (_feedExists(token, preferredQuote)) {
            return preferredPath;
        } else if (_feedExists(token, fallbackQuote)) {
            return fallbackPath;
        } else {
            return PricingPath.NONE;
        }
    }

    /// @notice Returns the price of `tokenIn` denominated in `tokenOut` at `target`
    function _fetchPrice(
        address tokenIn,
        address tokenOut,
        uint256 target,
        int8 factor
    ) internal view returns (uint256) {
        return target == 0 ? _fetchLatestPrice(tokenIn, tokenOut) : _fetchPriceAt(tokenIn, tokenOut, target, factor);
    }

    /// @notice Returns the latest price of `tokenIn` denominated in `tokenOut`
    function _fetchLatestPrice(address tokenIn, address tokenOut) internal view returns (uint256) {
        address feed = _feed(tokenIn, tokenOut);
        (, int256 price, , uint256 updatedAt, ) = _latestRoundData(feed);
        _revertIfPriceAfterTargetStale(block.timestamp, updatedAt);
        _revertIfPriceInvalid(price);
        return price.toUint256();
    }

    /// @notice Returns the historical price of `tokenIn` denominated in `tokenOut` at `target`.
    function _fetchPriceAt(
        address tokenIn,
        address tokenOut,
        uint256 target,
        int8 factor
    ) internal view returns (uint256) {
        UD60x18 cachedPriceAtTarget = _getCachedPriceAt(tokenIn, tokenOut, target);
        // NOTE: The cached prices are 18 decimals to maintain consistency across all adapters, because of this we need
        // to downscale the cached price the precision used by the feed before calculating the final price
        if (cachedPriceAtTarget > ZERO) return _scale(cachedPriceAtTarget.unwrap(), -int8(factor));

        address feed = _feed(tokenIn, tokenOut);
        (uint80 roundId, int256 price, , uint256 updatedAt, ) = _latestRoundData(feed);
        (uint16 phaseId, uint64 nextAggregatorRoundId) = ChainlinkAdapterStorage.parseRoundId(roundId);

        BinarySearchDataInternal memory binarySearchData;

        // if latest round data is on right side of target, search for round data closest to the target
        if (updatedAt > target) {
            binarySearchData.rightPrice = price;
            binarySearchData.rightUpdatedAt = updatedAt;

            binarySearchData = _performBinarySearchForRoundData(
                binarySearchData,
                feed,
                phaseId,
                nextAggregatorRoundId,
                target
            );

            price = binarySearchData.rightPrice;
            updatedAt = binarySearchData.rightUpdatedAt;

            if (
                binarySearchData.leftUpdatedAt > 0 &&
                target - binarySearchData.leftUpdatedAt <= binarySearchData.rightUpdatedAt - target
            ) {
                price = binarySearchData.leftPrice;
                updatedAt = binarySearchData.leftUpdatedAt;
            }
        }

        _revertIfPriceAfterTargetStale(target, updatedAt);
        _revertIfPriceInvalid(price);

        return price.toUint256();
    }

    /// @notice Performs a binary search to find the round data closest to the target timestamp
    function _performBinarySearchForRoundData(
        BinarySearchDataInternal memory binarySearchData,
        address feed,
        uint16 phaseId,
        uint64 nextAggregatorRoundId,
        uint256 target
    ) internal view returns (BinarySearchDataInternal memory) {
        uint64 lowestAggregatorRoundId = 0;
        uint64 highestAggregatorRoundId = nextAggregatorRoundId;

        uint80 roundId;
        int256 price;
        uint256 updatedAt;

        while (lowestAggregatorRoundId <= highestAggregatorRoundId) {
            nextAggregatorRoundId = lowestAggregatorRoundId + (highestAggregatorRoundId - lowestAggregatorRoundId) / 2;
            roundId = ChainlinkAdapterStorage.formatRoundId(phaseId, nextAggregatorRoundId);
            (, price, , updatedAt, ) = _getRoundData(feed, roundId);

            if (target == updatedAt) {
                binarySearchData.leftPrice = price;
                binarySearchData.leftUpdatedAt = updatedAt;
                break;
            }

            if (target > updatedAt) {
                binarySearchData.leftPrice = price;
                binarySearchData.leftUpdatedAt = updatedAt;
                lowestAggregatorRoundId = nextAggregatorRoundId + 1;
            } else {
                binarySearchData.rightPrice = price;
                binarySearchData.rightUpdatedAt = updatedAt;

                if (nextAggregatorRoundId == 0) break;
                highestAggregatorRoundId = nextAggregatorRoundId - 1;
            }
        }

        return binarySearchData;
    }

    /// @notice Try/Catch wrapper for Chainlink aggregator's latestRoundData() function
    function _latestRoundData(address feed) internal view returns (uint80, int256, uint256, uint256, uint80) {
        try AggregatorProxyInterface(feed).latestRoundData() returns (
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

    /// @notice Try/Catch wrapper for Chainlink aggregator's getRoundData() function
    function _getRoundData(
        address feed,
        uint80 roundId
    ) internal view returns (uint80, int256, uint256, uint256, uint80) {
        try AggregatorProxyInterface(feed).getRoundData(roundId) returns (
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

    /// @notice Returns the Chainlink aggregator for pair `tokenA` and `tokenB`
    function _aggregator(address tokenA, address tokenB) internal view returns (address[] memory aggregator) {
        address feed = _feed(tokenA, tokenB);
        aggregator = new address[](1);
        aggregator[0] = AggregatorProxyInterface(feed).aggregator();
    }

    /// @notice Returns decimals for `aggregator`
    function _aggregatorDecimals(address aggregator) internal view returns (uint8) {
        return AggregatorProxyInterface(aggregator).decimals();
    }

    /// @notice Returns the scaled price of `token` denominated in USD at `target`
    function _getPriceAgainstUSD(address token, uint256 target) internal view returns (UD60x18) {
        int8 factor = int8(ETH_DECIMALS - FOREX_DECIMALS);
        return token.isUSD() ? ONE : ud(_scale(_fetchPrice(token, Denominations.USD, target, factor), factor));
    }

    /// @notice Returns the scaled price of `token` denominated in ETH at `target`
    function _getPriceAgainstETH(address token, uint256 target) internal view returns (UD60x18) {
        return token.isETH() ? ONE : ud(_fetchPrice(token, Denominations.ETH, target, 0));
    }

    /// @notice Returns the scaled price of ETH denominated in USD at `target`
    function _getETHUSD(uint256 target) internal view returns (UD60x18) {
        int8 factor = int8(ETH_DECIMALS - FOREX_DECIMALS);
        return ud(_scale(_fetchPrice(Denominations.ETH, Denominations.USD, target, factor), factor));
    }

    /// @notice Returns the scaled price of BTC denominated in USD at `target`
    function _getBTCUSD(uint256 target) internal view returns (UD60x18) {
        int8 factor = int8(ETH_DECIMALS - FOREX_DECIMALS);
        return ud(_scale(_fetchPrice(Denominations.BTC, Denominations.USD, target, factor), factor));
    }

    /// @notice Returns the scaled price of WBTC denominated in BTC at `target`
    function _getWBTCBTC(uint256 target) internal view returns (UD60x18) {
        int8 factor = int8(ETH_DECIMALS - FOREX_DECIMALS);
        return ud(_scale(_fetchPrice(WRAPPED_BTC_TOKEN, Denominations.BTC, target, factor), factor));
    }

    /// @notice Revert if price is stale and MAX_DELAY has not passed
    function _revertIfPriceAfterTargetStale(uint256 target, uint256 updatedAt) internal view {
        if (target >= updatedAt && block.timestamp - target < MAX_DELAY && target - updatedAt > PRICE_STALE_THRESHOLD)
            revert ChainlinkAdapter__PriceAfterTargetIsStale(target, updatedAt, block.timestamp);
    }
}

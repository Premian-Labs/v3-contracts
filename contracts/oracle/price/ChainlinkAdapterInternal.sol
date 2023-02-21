// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {TokenSorting} from "../../libraries/TokenSorting.sol";
import {UD60x18} from "../../libraries/prbMath/UD60x18.sol";

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
    using UD60x18 for uint256;

    int256 private constant FOREX_DECIMALS = 8;
    int256 private constant ETH_DECIMALS = 18;

    uint256 private constant ONE_USD = 10 ** uint256(FOREX_DECIMALS);
    uint256 private constant ONE_ETH = 10 ** uint256(ETH_DECIMALS);
    uint256 private constant ONE_BTC = 10 ** uint256(FOREX_DECIMALS);

    address private immutable WRAPPED_NATIVE_TOKEN;
    address private immutable WRAPPED_BTC_TOKEN;

    constructor(address _wrappedNativeToken, address _wrappedBTCToken) {
        WRAPPED_NATIVE_TOKEN = _wrappedNativeToken;
        WRAPPED_BTC_TOKEN = _wrappedBTCToken;
    }

    /// @dev Expects `mappedTokenIn` and `mappedTokenOut` to be unsorted
    function _quote(
        PricingPath path,
        address mappedTokenIn,
        address mappedTokenOut
    ) internal view returns (uint256) {
        if (path <= PricingPath.TOKEN_ETH) {
            return _getDirectPrice(mappedTokenIn, mappedTokenOut, path);
        } else if (path <= PricingPath.TOKEN_ETH_TOKEN) {
            return _getPriceSameBase(mappedTokenIn, mappedTokenOut, path);
        } else if (path <= PricingPath.A_ETH_USD_B) {
            return _getPriceDifferentBases(mappedTokenIn, mappedTokenOut, path);
        } else {
            return _getPriceWBTCPrice(mappedTokenIn, mappedTokenOut);
        }
    }

    function _upsertPair(address tokenA, address tokenB) internal {
        (
            address mappedTokenA,
            address mappedTokenB
        ) = _mapToDenominationAndSort(tokenA, tokenB);

        PricingPath path = _determinePricingPath(mappedTokenA, mappedTokenB);
        bytes32 keyForPair = _keyForSortedPair(mappedTokenA, mappedTokenB);

        ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage
            .layout();

        if (path == PricingPath.NONE) {
            // Check if there is a current path. If there is, it means that the pair was supported and it
            // lost support. In that case, we will remove the current path and continue working as expected.
            // If there was no supported path, and there still isn't, then we will fail
            PricingPath _currentPath = l.pathForPair[keyForPair];

            if (_currentPath == PricingPath.NONE) {
                revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);
            }
        }

        l.pathForPair[keyForPair] = path;
        emit UpdatedPathForPair(mappedTokenA, mappedTokenB, path);
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

        (address sortedA, address sortedB) = TokenSorting.sortTokens(
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
        address tokenIn,
        address tokenOut,
        PricingPath path
    ) internal view returns (uint256) {
        int256 factor = ETH_DECIMALS -
            (path == PricingPath.TOKEN_ETH ? ETH_DECIMALS : FOREX_DECIMALS);

        uint256 price;
        if (path == PricingPath.ETH_USD) {
            price = _getETHUSD();
        } else if (path == PricingPath.TOKEN_USD) {
            price = _getPriceAgainstUSD(_isUSD(tokenOut) ? tokenIn : tokenOut);
        } else if (path == PricingPath.TOKEN_ETH) {
            price = _getPriceAgainstETH(_isETH(tokenOut) ? tokenIn : tokenOut);
        }

        price = _scale(price, factor);

        bool invert = _isUSD(tokenIn) ||
            (path == PricingPath.TOKEN_ETH && _isETH(tokenIn));

        return invert ? price.inv() : price;
    }

    /// @dev Handles prices when both tokens share the same base (either ETH or USD)
    function _getPriceSameBase(
        address tokenIn,
        address tokenOut,
        PricingPath path
    ) internal view returns (uint256) {
        int256 diff = _decimals(tokenIn) - _decimals(tokenOut);
        int256 factor = ETH_DECIMALS - (diff > 0 ? diff : -diff);

        address base = path == PricingPath.TOKEN_USD_TOKEN
            ? Denominations.USD
            : Denominations.ETH;

        uint256 tokenInToBase = _callRegistry(tokenIn, base);
        uint256 tokenOutToBase = _callRegistry(tokenOut, base);

        uint256 adjustedTokenInToBase = _scale(tokenInToBase, factor);
        uint256 adjustedTokenOutToBase = _scale(tokenOutToBase, factor);

        return adjustedTokenInToBase.div(adjustedTokenOutToBase);
    }

    /// @dev Handles prices when one of the tokens uses ETH as the base, and the other USD
    function _getPriceDifferentBases(
        address tokenIn,
        address tokenOut,
        PricingPath path
    ) internal view returns (uint256) {
        int256 factor = ETH_DECIMALS - FOREX_DECIMALS;
        uint256 adjustedEthToUSDPrice = _scale(_getETHUSD(), factor);

        bool isTokenInUSD = (path == PricingPath.A_USD_ETH_B &&
            tokenIn < tokenOut) ||
            (path == PricingPath.A_ETH_USD_B && tokenIn > tokenOut);

        if (isTokenInUSD) {
            uint256 adjustedTokenInToUSD = _scale(
                _getPriceAgainstUSD(tokenIn),
                factor
            );

            uint256 tokenOutToETH = _getPriceAgainstETH(tokenOut);

            return
                adjustedTokenInToUSD.div(adjustedEthToUSDPrice).div(
                    tokenOutToETH
                );
        } else {
            uint256 tokenInToETH = _getPriceAgainstETH(tokenIn);

            uint256 adjustedTokenOutToUSD = _scale(
                _getPriceAgainstUSD(tokenOut),
                factor
            );

            return
                tokenInToETH.mul(adjustedEthToUSDPrice).div(
                    adjustedTokenOutToUSD
                );
        }
    }

    /// @dev Handles prices when the pair is token/WBTC
    function _getPriceWBTCPrice(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256) {
        bool isTokenInWBTC = _isWBTC(tokenIn);
        int256 factor = ETH_DECIMALS - FOREX_DECIMALS;

        uint256 adjustedWBTCToUSDPrice = _scale(_getWBTCBTC(), factor).mul(
            _scale(_getBTCUSD(), factor)
        );

        uint256 adjustedTokenToUSD = _scale(
            _getPriceAgainstUSD(!isTokenInWBTC ? tokenIn : tokenOut),
            factor
        );

        uint256 price = adjustedWBTCToUSDPrice.div(adjustedTokenToUSD);
        return !isTokenInWBTC ? price.inv() : price;
    }

    function _getPriceAgainstUSD(
        address token
    ) internal view returns (uint256) {
        return
            _isUSD(token) ? ONE_USD : _callRegistry(token, Denominations.USD);
    }

    function _getPriceAgainstETH(
        address token
    ) internal view returns (uint256) {
        return
            _isETH(token) ? ONE_ETH : _callRegistry(token, Denominations.ETH);
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

    function _scale(
        uint256 amount,
        int256 factor
    ) internal pure returns (uint256) {
        uint256 ten = 10E18;
        factor = factor * 1E18;

        if (factor < 0) {
            return amount.div(ten.pow((-factor).toUint256()));
        } else {
            return amount.mul(ten.pow(factor.toUint256()));
        }
    }

    function _decimals(address token) internal view returns (int256) {
        if (_isETH(token)) {
            return ETH_DECIMALS;
        } else if (_isUSD(token) || _isWBTC(token)) {
            return FOREX_DECIMALS;
        } else {
            return int256(uint256(IERC20Metadata(token).decimals()));
        }
    }

    function _callRegistry(
        address base,
        address quote
    ) internal view returns (uint256) {
        address feed = _feed(base, quote);
        int256 price = AggregatorInterface(feed).latestAnswer();
        if (price <= 0) revert OracleAdapter__InvalidPrice(price);
        return price.toUint256();
    }

    function _batchRegisterFeedMappings(
        FeedMappingArgs[] memory args
    ) internal {
        for (uint256 i = 0; i < args.length; i++) {
            address token = args[i].token;
            address denomination = args[i].denomination;

            if (token == denomination)
                revert OracleAdapter__TokensAreSame(token, denomination);

            if (token == address(0) || denomination == address(0))
                revert OracleAdapter__ZeroAddress();

            bytes32 keyForPair = _keyForUnsortedPair(token, denomination);
            ChainlinkAdapterStorage.layout().feeds[keyForPair] = args[i].feed;
        }

        emit FeedMappingsRegistered(args);
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
    function _denomination(address token) internal view returns (address) {
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

        return TokenSorting.sortTokens(mappedTokenA, mappedTokenB);
    }

    function _mapToDenomination(
        address tokenA,
        address tokenB
    ) internal view returns (address mappedTokenA, address mappedTokenB) {
        mappedTokenA = _denomination(tokenA);
        mappedTokenB = _denomination(tokenB);
    }

    function _keyForUnsortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address mappedTokenA, address mappedTokenB) = TokenSorting.sortTokens(
            tokenA,
            tokenB
        );

        return _keyForSortedPair(mappedTokenA, mappedTokenB);
    }

    /// @dev Expects `tokenA` and `tokenB` to be sorted
    function _keyForSortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA, tokenB));
    }

    function _getETHUSD() internal view returns (uint256) {
        return _callRegistry(Denominations.ETH, Denominations.USD);
    }

    function _getBTCUSD() internal view returns (uint256) {
        return _callRegistry(Denominations.BTC, Denominations.USD);
    }

    function _getWBTCBTC() internal view returns (uint256) {
        return _callRegistry(WRAPPED_BTC_TOKEN, Denominations.BTC);
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

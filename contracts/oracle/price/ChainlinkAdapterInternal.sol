// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";
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

    function _addOrModifySupportForPair(
        address tokenA,
        address tokenB
    ) internal virtual override {
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

    function _isPairSupported(
        address tokenA,
        address tokenB
    ) internal view virtual override returns (bool) {
        return _pathForPair(tokenA, tokenB) != PricingPath.NONE;
    }

    function _pathForPair(
        address tokenA,
        address tokenB
    ) internal view returns (PricingPath) {
        (
            address mappedTokenA,
            address mappedTokenB
        ) = _mapToDenominationAndSort(tokenA, tokenB);

        return
            ChainlinkAdapterStorage.layout().pathForPair[
                _keyForSortedPair(mappedTokenA, mappedTokenB)
            ];
    }

    function _pathForPairAndUnsortedMappedTokens(
        address tokenA,
        address tokenB
    )
        internal
        view
        returns (PricingPath path, address mappedTokenA, address mappedTokenB)
    {
        (mappedTokenA, mappedTokenB) = _mapPairToDenomination(tokenA, tokenB);

        path = ChainlinkAdapterStorage.layout().pathForPair[
            _keyForUnsortedPair(mappedTokenA, mappedTokenB)
        ];
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
        int256 diff = _getDecimals(tokenIn) - _getDecimals(tokenOut);
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
        bool isWBTC = _isWBTC(tokenIn);
        int256 factor = ETH_DECIMALS - FOREX_DECIMALS;

        uint256 adjustedWBTCToUSDPrice = _scale(_getWBTCBTC(), factor).mul(
            _scale(_getBTCUSD(), factor)
        );

        uint256 adjustedTokenToUSD = _scale(
            _getPriceAgainstUSD(!isWBTC ? tokenIn : tokenOut),
            factor
        );

        uint256 price = adjustedWBTCToUSDPrice.div(adjustedTokenToUSD);
        return !isWBTC ? price.inv() : price;
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

        if ((isTokenAETH && isTokenBUSD) || (isTokenAUSD && isTokenBETH)) {
            return PricingPath.ETH_USD;
        } else if (_isWBTC(tokenA) || _isWBTC(tokenB)) {
            return _tryWithBTCUSDBases(tokenB, PricingPath.TOKEN_WBTC);
        } else if (isTokenBUSD) {
            return
                _tryWithETHUSDBases(
                    tokenA,
                    PricingPath.TOKEN_USD,
                    PricingPath.A_ETH_USD_B
                );
        } else if (isTokenAUSD) {
            return
                _tryWithETHUSDBases(
                    tokenB,
                    PricingPath.TOKEN_USD,
                    PricingPath.A_USD_ETH_B
                );
        } else if (isTokenBETH) {
            return
                _tryWithETHUSDBases(
                    tokenA,
                    PricingPath.A_USD_ETH_B,
                    PricingPath.TOKEN_ETH
                );
        } else if (isTokenAETH) {
            return
                _tryWithETHUSDBases(
                    tokenB,
                    PricingPath.A_ETH_USD_B,
                    PricingPath.TOKEN_ETH
                );
        } else if (_exists(tokenA, Denominations.USD)) {
            return
                _tryWithETHUSDBases(
                    tokenB,
                    PricingPath.TOKEN_USD_TOKEN,
                    PricingPath.A_USD_ETH_B
                );
        } else if (_exists(tokenA, Denominations.ETH)) {
            return
                _tryWithETHUSDBases(
                    tokenB,
                    PricingPath.A_ETH_USD_B,
                    PricingPath.TOKEN_ETH_TOKEN
                );
        }

        return PricingPath.NONE;
    }

    function _tryWithBTCUSDBases(
        address token,
        PricingPath ifBTC
    ) internal view returns (PricingPath) {
        (address firstBase, address secondBaseBase) = (
            Denominations.USD,
            Denominations.BTC
        );

        if (_exists(token, firstBase) || _exists(token, secondBaseBase)) {
            return ifBTC;
        } else {
            return PricingPath.NONE;
        }
    }

    function _tryWithETHUSDBases(
        address token,
        PricingPath ifUSD,
        PricingPath ifETH
    ) internal view returns (PricingPath) {
        // Note: we are prioritizing paths that have fewer external calls
        (
            address firstBase,
            PricingPath firstResult,
            address secondBaseBase,
            PricingPath secondResult
        ) = ifUSD < ifETH
                ? (Denominations.USD, ifUSD, Denominations.ETH, ifETH)
                : (Denominations.ETH, ifETH, Denominations.USD, ifUSD);

        if (_exists(token, firstBase)) {
            return firstResult;
        } else if (_exists(token, secondBaseBase)) {
            return secondResult;
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

    function _getDecimals(address token) internal view returns (int256) {
        if (_isETH(token)) {
            return ETH_DECIMALS;
        } else if (!AddressUtils.isContract(token)) {
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

    /// @dev Should only map wrapped tokens which are guarenteed to have a 1:1 ratio
    function _denomination(address token) internal view returns (address) {
        return token == WRAPPED_NATIVE_TOKEN ? Denominations.ETH : token;
    }

    function _mapToDenominationAndSort(
        address tokenA,
        address tokenB
    ) internal view returns (address, address) {
        (address mappedTokenA, address mappedTokenB) = _mapPairToDenomination(
            tokenA,
            tokenB
        );

        return TokenSorting.sortTokens(mappedTokenA, mappedTokenB);
    }

    function _mapPairToDenomination(
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

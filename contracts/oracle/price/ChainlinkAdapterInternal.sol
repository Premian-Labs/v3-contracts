// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";

import {TokenSorting} from "../../libraries/TokenSorting.sol";
import {UD60x18} from "../../libraries/prbMath/UD60x18.sol";

import {FeedRegistryInterface, IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";
import {ChainlinkAdapterStorage} from "./ChainlinkAdapterStorage.sol";
import {OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract ChainlinkAdapterInternal is
    IChainlinkAdapterInternal,
    OracleAdapter
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;
    using UD60x18 for uint256;

    uint32 internal constant MAX_DELAY = 25 hours;
    FeedRegistryInterface internal immutable FeedRegistry;

    int256 private constant FOREX_DECIMALS = 8;
    int256 private constant ETH_DECIMALS = 18;
    uint256 private constant ONE_USD = 10 ** uint256(FOREX_DECIMALS);
    uint256 private constant ONE_ETH = 10 ** uint256(ETH_DECIMALS);

    constructor(
        FeedRegistryInterface _registry,
        address[] memory _addresses,
        address[] memory _mappings
    ) {
        if (address(_registry) == address(0)) revert Oracle__ZeroAddress();
        FeedRegistry = _registry;
        _addMappings(_addresses, _mappings);
    }

    function _addOrModifySupportForPair(
        address tokenA,
        address tokenB
    ) internal virtual override {
        (address _tokenA, address _tokenB) = _mapAndSort(tokenA, tokenB);
        PricingPath path = _determinePricingPath(_tokenA, _tokenB);
        bytes32 keyForPair = _keyForSortedPair(_tokenA, _tokenB);

        ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage
            .layout();

        if (path == PricingPath.NONE) {
            // Check if there is a current path. If there is, it means that the pair was supported and it
            // lost support. In that case, we will remove the current path and continue working as expected.
            // If there was no supported path, and there still isn't, then we will fail
            PricingPath _currentPath = l.pathForPair[keyForPair];

            if (_currentPath == PricingPath.NONE) {
                revert Oracle__PairCannotBeSupported(tokenA, tokenB);
            }
        }

        l.pathForPair[keyForPair] = path;
        emit UpdatedPathForPair(_tokenA, _tokenB, path);
    }

    function _isPairAlreadySupported(
        address tokenA,
        address tokenB
    ) internal view virtual override(OracleAdapter) returns (bool) {
        return _pathForPair(tokenA, tokenB) != PricingPath.NONE;
    }

    function _pathForPair(
        address tokenA,
        address tokenB
    ) internal view returns (PricingPath) {
        (address _tokenA, address _tokenB) = _mapAndSort(tokenA, tokenB);
        return
            ChainlinkAdapterStorage.layout().pathForPair[
                _keyForSortedPair(_tokenA, _tokenB)
            ];
    }

    /// @dev Handles prices when the pair is either ETH/USD, token/ETH or token/USD
    function _getDirectPrice(
        address tokenIn,
        address tokenOut,
        PricingPath path
    ) internal view returns (uint256) {
        int256 scaleBy = ETH_DECIMALS -
            (
                path == PricingPath.TOKEN_ETH_PAIR
                    ? ETH_DECIMALS
                    : FOREX_DECIMALS
            );

        uint256 price;
        if (path == PricingPath.ETH_USD_PAIR) {
            price = _getETHUSD();
        } else if (path == PricingPath.TOKEN_USD_PAIR) {
            price = _getPriceAgainstUSD(_isUSD(tokenOut) ? tokenIn : tokenOut);
        } else if (path == PricingPath.TOKEN_ETH_PAIR) {
            price = _getPriceAgainstETH(_isETH(tokenOut) ? tokenIn : tokenOut);
        }

        price = _adjustDecimals(price, scaleBy);

        bool invert = _isUSD(tokenIn) ||
            (path == PricingPath.TOKEN_ETH_PAIR && _isETH(tokenIn));

        return invert ? price.inv() : price;
    }

    /// @dev Handles prices when both tokens share the same base (either ETH or USD)
    function _getPriceSameBase(
        address tokenIn,
        address tokenOut,
        PricingPath path
    ) internal view returns (uint256) {
        int256 diff = _getDecimals(tokenIn) - _getDecimals(tokenOut);
        int256 scaleBy = ETH_DECIMALS - (diff > 0 ? diff : -diff);

        address base = path == PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR
            ? Denominations.USD
            : Denominations.ETH;

        uint256 tokenInToBase = _callRegistry(tokenIn, base);
        uint256 tokenOutToBase = _callRegistry(tokenOut, base);

        uint256 adjustedTokenInToBase = _adjustDecimals(tokenInToBase, scaleBy);

        uint256 adjustedTokenOutToBase = _adjustDecimals(
            tokenOutToBase,
            scaleBy
        );

        return adjustedTokenInToBase.div(adjustedTokenOutToBase);
    }

    /// @dev Handles prices when one of the tokens uses ETH as the base, and the other USD
    function _getPriceDifferentBases(
        address tokenIn,
        address tokenOut,
        PricingPath path
    ) internal view returns (uint256) {
        int256 scaleBy = ETH_DECIMALS - FOREX_DECIMALS;
        uint256 adjustedEthToUSDPrice = _adjustDecimals(_getETHUSD(), scaleBy);

        bool isTokenInUSD = (path ==
            PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B &&
            tokenIn < tokenOut) ||
            (path == PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B &&
                tokenIn > tokenOut);

        if (isTokenInUSD) {
            uint256 adjustedTokenInToUSD = _adjustDecimals(
                _getPriceAgainstUSD(tokenIn),
                scaleBy
            );

            uint256 tokenOutToETH = _getPriceAgainstETH(tokenOut);

            return
                adjustedTokenInToUSD.div(adjustedEthToUSDPrice).div(
                    tokenOutToETH
                );
        } else {
            uint256 tokenInToETH = _getPriceAgainstETH(tokenIn);

            uint256 adjustedTokenOutToUSD = _adjustDecimals(
                _getPriceAgainstUSD(tokenOut),
                scaleBy
            );

            return
                tokenInToETH.mul(adjustedEthToUSDPrice).div(
                    adjustedTokenOutToUSD
                );
        }
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
            revert Oracle__BaseAndQuoteAreSame(tokenA, tokenB);

        bool isTokenAUSD = _isUSD(tokenA);
        bool isTokenBUSD = _isUSD(tokenB);
        bool isTokenAETH = _isETH(tokenA);
        bool isTokenBETH = _isETH(tokenB);

        if ((isTokenAETH && isTokenBUSD) || (isTokenAUSD && isTokenBETH)) {
            return PricingPath.ETH_USD_PAIR;
        } else if (isTokenBUSD) {
            return
                _tryWithBases(
                    tokenA,
                    PricingPath.TOKEN_USD_PAIR,
                    PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B
                );
        } else if (isTokenAUSD) {
            return
                _tryWithBases(
                    tokenB,
                    PricingPath.TOKEN_USD_PAIR,
                    PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
                );
        } else if (isTokenBETH) {
            return
                _tryWithBases(
                    tokenA,
                    PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B,
                    PricingPath.TOKEN_ETH_PAIR
                );
        } else if (isTokenAETH) {
            return
                _tryWithBases(
                    tokenB,
                    PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
                    PricingPath.TOKEN_ETH_PAIR
                );
        } else if (_exists(tokenA, Denominations.USD)) {
            return
                _tryWithBases(
                    tokenB,
                    PricingPath.TOKEN_TO_USD_TO_TOKEN_PAIR,
                    PricingPath.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
                );
        } else if (_exists(tokenA, Denominations.ETH)) {
            return
                _tryWithBases(
                    tokenB,
                    PricingPath.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
                    PricingPath.TOKEN_TO_ETH_TO_TOKEN_PAIR
                );
        }

        return PricingPath.NONE;
    }

    function _tryWithBases(
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
        try FeedRegistry.latestRoundData(base, quote) returns (
            uint80,
            int256 price,
            uint256,
            uint256,
            uint80
        ) {
            return price > 0;
        } catch {
            return false;
        }
    }

    function _adjustDecimals(
        uint256 amount,
        int256 factor
    ) internal pure returns (uint256) {
        uint256 ten = 10E18;
        factor = factor * 1E18;

        if (factor < 0) {
            return amount.div(ten.pow(uint256(-factor)));
        } else {
            return amount.mul(ten.pow(uint256(factor)));
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
        (, int256 price, , uint256 updatedAt, ) = FeedRegistry.latestRoundData(
            base,
            quote
        );
        if (price <= 0) revert Oracle__InvalidPrice();

        if (block.timestamp > updatedAt + MAX_DELAY)
            revert Oracle__LastUpdateIsTooOld();

        return uint256(price);
    }

    function _addMappings(
        address[] memory addresses,
        address[] memory mappings
    ) internal {
        if (addresses.length != mappings.length)
            revert Oracle__InvalidMappingsInput();

        for (uint256 i = 0; i < addresses.length; i++) {
            ChainlinkAdapterStorage.layout().tokenMappings[
                addresses[i]
            ] = mappings[i];
        }

        emit MappingsAdded(addresses, mappings);
    }

    function _mappedToken(address token) internal view returns (address) {
        address tokenMapping = ChainlinkAdapterStorage.layout().tokenMappings[
            token
        ];

        return tokenMapping != address(0) ? tokenMapping : token;
    }

    function _mapAndSort(
        address tokenA,
        address tokenB
    ) internal view returns (address, address) {
        (address _mappedTokenA, address _mappedTokenB) = _mapPair(
            tokenA,
            tokenB
        );

        return TokenSorting.sortTokens(_mappedTokenA, _mappedTokenB);
    }

    function _mapPair(
        address tokenA,
        address tokenB
    ) internal view returns (address _mappedTokenA, address _mappedTokenB) {
        _mappedTokenA = _mappedToken(tokenA);
        _mappedTokenB = _mappedToken(tokenB);
    }

    function _keyForUnsortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        (address _tokenA, address _tokenB) = TokenSorting.sortTokens(
            tokenA,
            tokenB
        );

        return _keyForSortedPair(_tokenA, _tokenB);
    }

    /// @dev Expects `tokenA` and `tokenB` to be sorted
    function _keyForSortedPair(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenA, tokenB));
    }

    function _getETHUSD() internal view returns (uint256) {
        return _callRegistry(Denominations.ETH, Denominations.USD);
    }

    function _isUSD(address token) internal pure returns (bool) {
        return token == Denominations.USD;
    }

    function _isETH(address token) internal pure returns (bool) {
        return token == Denominations.ETH;
    }
}

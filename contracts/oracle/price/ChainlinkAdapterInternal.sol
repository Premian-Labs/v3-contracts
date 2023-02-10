// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {AddressUtils} from "@solidstate/contracts/utils/AddressUtils.sol";

import {TokenSorting} from "../../libraries/TokenSorting.sol";
import {UD60x18} from "../../libraries/prbMath/UD60x18.sol";

import {FeedRegistryInterface, IChainlinkAdapterInternal} from "./IChainlinkAdapterInternal.sol";
import {OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract ChainlinkAdapterInternal is
    IChainlinkAdapterInternal,
    OracleAdapter
{
    using UD60x18 for uint256;

    uint32 internal constant MAX_DELAY = 25 hours;
    FeedRegistryInterface internal immutable FeedRegistry;

    int256 private constant FOREX_DECIMALS = 8;
    int256 private constant ETH_DECIMALS = 18;
    uint256 private constant ONE_USD = 10 ** uint256(FOREX_DECIMALS);
    uint256 private constant ONE_ETH = 10 ** uint256(ETH_DECIMALS);

    mapping(address => address) internal _tokenMappings;
    mapping(bytes32 => PricingPlan) internal _planForPair;

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
        address _tokenA,
        address _tokenB,
        bytes calldata
    ) internal virtual override {
        (address __tokenA, address __tokenB) = _mapAndSort(_tokenA, _tokenB);
        PricingPlan _plan = _determinePricingPlan(__tokenA, __tokenB);
        bytes32 _keyForPair = _keyForSortedPair(__tokenA, __tokenB);

        if (_plan == PricingPlan.NONE) {
            // Check if there is a current plan. If there is, it means that the pair was supported and it
            // lost support. In that case, we will remove the current plan and continue working as expected.
            // If there was no supported plan, and there still isn't, then we will fail
            PricingPlan _currentPlan = _planForPair[_keyForPair];

            if (_currentPlan == PricingPlan.NONE) {
                revert Oracle__PairCannotBeSupported(_tokenA, _tokenB);
            }
        }

        _planForPair[_keyForPair] = _plan;
        emit UpdatedPlanForPair(__tokenA, __tokenB, _plan);
    }

    /// @dev Handles prices when the pair is either ETH/USD, token/ETH or token/USD
    function _getDirectPrice(
        address _tokenIn,
        address _tokenOut,
        PricingPlan _plan
    ) internal view returns (uint256) {
        int256 _scaleBy = ETH_DECIMALS -
            (
                _plan == PricingPlan.TOKEN_ETH_PAIR
                    ? ETH_DECIMALS
                    : FOREX_DECIMALS
            );

        uint256 _price;
        if (_plan == PricingPlan.ETH_USD_PAIR) {
            _price = _getETHUSD();
        } else if (_plan == PricingPlan.TOKEN_USD_PAIR) {
            _price = _getPriceAgainstUSD(
                _isUSD(_tokenOut) ? _tokenIn : _tokenOut
            );
        } else if (_plan == PricingPlan.TOKEN_ETH_PAIR) {
            _price = _getPriceAgainstETH(
                _isETH(_tokenOut) ? _tokenIn : _tokenOut
            );
        }

        _price = _adjustDecimals(_price, _scaleBy);

        bool invert = _isUSD(_tokenIn) ||
            (_plan == PricingPlan.TOKEN_ETH_PAIR && _isETH(_tokenIn));

        return invert ? _price.inv() : _price;
    }

    /// @dev Handles prices when both tokens share the same base (either ETH or USD)
    function _getPriceSameBase(
        address _tokenIn,
        address _tokenOut,
        PricingPlan _plan
    ) internal view returns (uint256) {
        int256 _diff = _getDecimals(_tokenIn) - _getDecimals(_tokenOut);
        int256 _scaleBy = ETH_DECIMALS - (_diff > 0 ? _diff : _diff * -1);

        address _base = _plan == PricingPlan.TOKEN_TO_USD_TO_TOKEN_PAIR
            ? Denominations.USD
            : Denominations.ETH;

        uint256 _tokenInToBase = _callRegistry(_tokenIn, _base);
        uint256 _tokenOutToBase = _callRegistry(_tokenOut, _base);

        uint256 adjustedTokenInToBase = _adjustDecimals(
            _tokenInToBase,
            _scaleBy
        );

        uint256 adjustedTokenOutToBase = _adjustDecimals(
            _tokenOutToBase,
            _scaleBy
        );

        return adjustedTokenInToBase.div(adjustedTokenOutToBase);
    }

    /// @dev Handles prices when one of the tokens uses ETH as the base, and the other USD
    function _getPriceDifferentBases(
        address _tokenIn,
        address _tokenOut,
        PricingPlan _plan
    ) internal view returns (uint256) {
        int256 _scaleBy = ETH_DECIMALS - FOREX_DECIMALS;
        uint256 adjustedEthToUSDPrice = _adjustDecimals(_getETHUSD(), _scaleBy);

        bool _isTokenInUSD = (_plan ==
            PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B &&
            _tokenIn < _tokenOut) ||
            (_plan == PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B &&
                _tokenIn > _tokenOut);

        if (_isTokenInUSD) {
            uint256 adjustedTokenInToUSD = _adjustDecimals(
                _getPriceAgainstUSD(_tokenIn),
                _scaleBy
            );

            uint256 _tokenOutToETH = _getPriceAgainstETH(_tokenOut);

            return
                adjustedTokenInToUSD.div(adjustedEthToUSDPrice).div(
                    _tokenOutToETH
                );
        } else {
            uint256 _tokenInToETH = _getPriceAgainstETH(_tokenIn);

            uint256 adjustedTokenOutToUSD = _adjustDecimals(
                _getPriceAgainstUSD(_tokenOut),
                _scaleBy
            );

            return
                _tokenInToETH.mul(adjustedEthToUSDPrice).div(
                    adjustedTokenOutToUSD
                );
        }
    }

    function _getPriceAgainstUSD(
        address _token
    ) internal view returns (uint256) {
        return
            _isUSD(_token) ? ONE_USD : _callRegistry(_token, Denominations.USD);
    }

    function _getPriceAgainstETH(
        address _token
    ) internal view returns (uint256) {
        return
            _isETH(_token) ? ONE_ETH : _callRegistry(_token, Denominations.ETH);
    }

    /// @dev Expects `_tokenA` and `_tokenB` to be sorted
    function _determinePricingPlan(
        address _tokenA,
        address _tokenB
    ) internal view virtual returns (PricingPlan) {
        if (_tokenA == _tokenB)
            revert Oracle__BaseAndQuoteAreSame(_tokenA, _tokenB);

        bool _isTokenAUSD = _isUSD(_tokenA);
        bool _isTokenBUSD = _isUSD(_tokenB);
        bool _isTokenAETH = _isETH(_tokenA);
        bool _isTokenBETH = _isETH(_tokenB);

        if ((_isTokenAETH && _isTokenBUSD) || (_isTokenAUSD && _isTokenBETH)) {
            return PricingPlan.ETH_USD_PAIR;
        } else if (_isTokenBUSD) {
            return
                _tryWithBases(
                    _tokenA,
                    PricingPlan.TOKEN_USD_PAIR,
                    PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B
                );
        } else if (_isTokenAUSD) {
            return
                _tryWithBases(
                    _tokenB,
                    PricingPlan.TOKEN_USD_PAIR,
                    PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
                );
        } else if (_isTokenBETH) {
            return
                _tryWithBases(
                    _tokenA,
                    PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B,
                    PricingPlan.TOKEN_ETH_PAIR
                );
        } else if (_isTokenAETH) {
            return
                _tryWithBases(
                    _tokenB,
                    PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
                    PricingPlan.TOKEN_ETH_PAIR
                );
        } else if (_exists(_tokenA, Denominations.USD)) {
            return
                _tryWithBases(
                    _tokenB,
                    PricingPlan.TOKEN_TO_USD_TO_TOKEN_PAIR,
                    PricingPlan.TOKEN_A_TO_USD_TO_ETH_TO_TOKEN_B
                );
        } else if (_exists(_tokenA, Denominations.ETH)) {
            return
                _tryWithBases(
                    _tokenB,
                    PricingPlan.TOKEN_A_TO_ETH_TO_USD_TO_TOKEN_B,
                    PricingPlan.TOKEN_TO_ETH_TO_TOKEN_PAIR
                );
        }

        return PricingPlan.NONE;
    }

    function _tryWithBases(
        address _token,
        PricingPlan _ifUSD,
        PricingPlan _ifETH
    ) internal view returns (PricingPlan) {
        // Note: we are prioritizing plans that have fewer external calls
        (
            address _firstBase,
            PricingPlan _firstResult,
            address _secondBaseBase,
            PricingPlan _secondResult
        ) = _ifUSD < _ifETH
                ? (Denominations.USD, _ifUSD, Denominations.ETH, _ifETH)
                : (Denominations.ETH, _ifETH, Denominations.USD, _ifUSD);

        if (_exists(_token, _firstBase)) {
            return _firstResult;
        } else if (_exists(_token, _secondBaseBase)) {
            return _secondResult;
        } else {
            return PricingPlan.NONE;
        }
    }

    function _exists(
        address _base,
        address _quote
    ) internal view returns (bool) {
        try FeedRegistry.latestRoundData(_base, _quote) returns (
            uint80,
            int256 _price,
            uint256,
            uint256,
            uint80
        ) {
            return _price > 0;
        } catch {
            return false;
        }
    }

    function _adjustDecimals(
        uint256 _amount,
        int256 _factor
    ) internal pure returns (uint256) {
        uint256 ten = 10E18;
        _factor = _factor * 1E18;

        if (_factor < 0) {
            return _amount.div(ten.pow(uint256(-_factor)));
        } else {
            return _amount.mul(ten.pow(uint256(_factor)));
        }
    }

    function _getDecimals(address _token) internal view returns (int256) {
        if (_isETH(_token)) {
            return ETH_DECIMALS;
        } else if (!AddressUtils.isContract(_token)) {
            return FOREX_DECIMALS;
        } else {
            return int256(uint256(IERC20Metadata(_token).decimals()));
        }
    }

    function _callRegistry(
        address _base,
        address _quote
    ) internal view returns (uint256) {
        (, int256 _price, , uint256 _updatedAt, ) = FeedRegistry
            .latestRoundData(_base, _quote);
        if (_price <= 0) revert Oracle__InvalidPrice();

        if (block.timestamp > _updatedAt + MAX_DELAY)
            revert Oracle__LastUpdateIsTooOld();

        return uint256(_price);
    }

    function _addMappings(
        address[] memory _addresses,
        address[] memory _mappings
    ) internal {
        if (_addresses.length != _mappings.length)
            revert Oracle__InvalidMappingsInput();

        for (uint256 i = 0; i < _addresses.length; i++) {
            _tokenMappings[_addresses[i]] = _mappings[i];
        }

        emit MappingsAdded(_addresses, _mappings);
    }

    function _mappedToken(address _token) internal view returns (address) {
        address _mapping = _tokenMappings[_token];
        return _mapping != address(0) ? _mapping : _token;
    }

    function _mapAndSort(
        address _tokenA,
        address _tokenB
    ) internal view returns (address, address) {
        (address _mappedTokenA, address _mappedTokenB) = _mapPair(
            _tokenA,
            _tokenB
        );

        return TokenSorting.sortTokens(_mappedTokenA, _mappedTokenB);
    }

    function _mapPair(
        address _tokenA,
        address _tokenB
    ) internal view returns (address _mappedTokenA, address _mappedTokenB) {
        _mappedTokenA = _mappedToken(_tokenA);
        _mappedTokenB = _mappedToken(_tokenB);
    }

    function _keyForUnsortedPair(
        address _tokenA,
        address _tokenB
    ) internal pure returns (bytes32) {
        (address __tokenA, address __tokenB) = TokenSorting.sortTokens(
            _tokenA,
            _tokenB
        );

        return _keyForSortedPair(__tokenA, __tokenB);
    }

    /// @dev Expects `_tokenA` and `_tokenB` to be sorted
    function _keyForSortedPair(
        address _tokenA,
        address _tokenB
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_tokenA, _tokenB));
    }

    function _getETHUSD() internal view returns (uint256) {
        return _callRegistry(Denominations.ETH, Denominations.USD);
    }

    function _isUSD(address _token) internal pure returns (bool) {
        return _token == Denominations.USD;
    }

    function _isETH(address _token) internal pure returns (bool) {
        return _token == Denominations.ETH;
    }
}

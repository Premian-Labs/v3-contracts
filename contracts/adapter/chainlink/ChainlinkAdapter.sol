// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {UD60x18} from "@prb/math/UD60x18.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {IOracleAdapter} from "../IOracleAdapter.sol";
import {OracleAdapter} from "../OracleAdapter.sol";
import {ETH_DECIMALS, Tokens} from "../Tokens.sol";

import {ChainlinkAdapterInternal} from "./ChainlinkAdapterInternal.sol";
import {ChainlinkAdapterStorage} from "./ChainlinkAdapterStorage.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";

/// @title An implementation of IOracleAdapter that uses Chainlink feeds
/// @notice This oracle adapter will attempt to use all available feeds to determine prices between pairs
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    OracleAdapter
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;
    using Tokens for address;

    constructor(
        address _wrappedNativeToken,
        address _wrappedBTCToken
    ) ChainlinkAdapterInternal(_wrappedNativeToken, _wrappedBTCToken) {}

    /// @inheritdoc IOracleAdapter
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view returns (bool isCached, bool hasPath) {
        (
            PricingPath path,
            address mappedTokenA,
            address mappedTokenB
        ) = _pricingPath(tokenA, tokenB, true);

        isCached = path != PricingPath.NONE;

        if (isCached) return (isCached, true);

        hasPath =
            _determinePricingPath(mappedTokenA, mappedTokenB) !=
            PricingPath.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function upsertPair(address tokenA, address tokenB) external {
        (
            address mappedTokenA,
            address mappedTokenB
        ) = _mapToDenominationAndSort(tokenA, tokenB);

        PricingPath path = _determinePricingPath(mappedTokenA, mappedTokenB);
        bytes32 keyForPair = mappedTokenA.keyForSortedPair(mappedTokenB);

        ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage
            .layout();

        if (path == PricingPath.NONE) {
            // Check if there is a current path. If there is, it means that the pair was supported and it
            // lost support. In that case, we will remove the current path and continue working as expected.
            // If there was no supported path, and there still isn't, then we will fail
            PricingPath _currentPath = l.pricingPath[keyForPair];

            if (_currentPath == PricingPath.NONE)
                revert OracleAdapter__PairCannotBeSupported(tokenA, tokenB);
        }

        if (l.pricingPath[keyForPair] == path) return;
        l.pricingPath[keyForPair] = path;
        emit UpdatedPathForPair(mappedTokenA, mappedTokenB, path);
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (UD60x18) {
        return _quoteFrom(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (UD60x18) {
        _ensureTargetNonZero(target);
        return _quoteFrom(tokenIn, tokenOut, target);
    }

    /// @inheritdoc IOracleAdapter
    function describePricingPath(
        address token
    )
        external
        view
        returns (
            AdapterType adapterType,
            address[][] memory path,
            uint8[] memory decimals
        )
    {
        adapterType = AdapterType.CHAINLINK;
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
            decimals[0] = path[0][0] == Denominations.ETH
                ? ETH_DECIMALS
                : _aggregatorDecimals(path[0][0]);
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
            _resizeArray(decimals, 0);
        } else if (decimals[1] == 0) {
            _resizeArray(decimals, 1);
        }
    }

    /// @inheritdoc IChainlinkAdapter
    function pricingPath(
        address tokenA,
        address tokenB
    ) external view returns (PricingPath) {
        (PricingPath path, , ) = _pricingPath(tokenA, tokenB, false);
        return path;
    }
}

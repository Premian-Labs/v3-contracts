// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";

import {ChainlinkAdapterInternal, ChainlinkAdapterStorage} from "./ChainlinkAdapterInternal.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    OracleAdapter,
    SafeOwnable
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;

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
        ) = _pathForPair(tokenA, tokenB, true);

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

        if (l.pathForPair[keyForPair] == path) return;

        l.pathForPair[keyForPair] = path;
        emit UpdatedPathForPair(mappedTokenA, mappedTokenB, path);
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut
    ) external view returns (uint256) {
        return _quoteFrom(tokenIn, tokenOut, 0);
    }

    /// @inheritdoc IOracleAdapter
    function quoteFrom(
        address tokenIn,
        address tokenOut,
        uint256 target
    ) external view returns (uint256) {
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
        } else if (_exists(token, Denominations.ETH)) {
            path[0] = _aggregator(token, Denominations.ETH);
        } else if (_exists(token, Denominations.USD)) {
            path[0] = _aggregator(token, Denominations.USD);
            path[1] = _aggregator(Denominations.ETH, Denominations.USD);
        }

        if (path[0].length > 0) {
            decimals[0] = path[0][0] == Denominations.ETH
                ? 18
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
            uint8[] memory temp = decimals;
            _resizeArray(temp, 0);
            decimals = temp;
        } else if (decimals[1] == 0) {
            uint8[] memory temp = decimals;
            _resizeArray(temp, 1);
            decimals = temp;
        }
    }

    /// @inheritdoc IChainlinkAdapter
    function pathForPair(
        address tokenA,
        address tokenB
    ) external view returns (PricingPath) {
        (PricingPath path, , ) = _pathForPair(tokenA, tokenB, false);
        return path;
    }

    /// @inheritdoc IChainlinkAdapter
    function batchRegisterFeedMappings(
        FeedMappingArgs[] memory args
    ) external onlyOwner {
        for (uint256 i = 0; i < args.length; i++) {
            address token = _tokenToDenomination(args[i].token);
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

    /// @inheritdoc IChainlinkAdapter
    function feed(
        address tokenA,
        address tokenB
    ) external view returns (address) {
        (address mappedTokenA, address mappedTokenB) = _mapToDenomination(
            tokenA,
            tokenB
        );

        return _feed(mappedTokenA, mappedTokenB);
    }
}

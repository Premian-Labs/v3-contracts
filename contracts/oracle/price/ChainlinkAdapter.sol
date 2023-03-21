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
        _upsertPair(tokenA, tokenB);
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
        returns (AdapterType, address, address[][] memory, uint8[] memory)
    {
        // there are no tiers on chainlink so this is essentially a placeholder
        address[][] memory tier = new address[][](1);
        address[] memory path = new address[](2);
        token = _tokenToDenomination(token);

        if (_exists(token, Denominations.USD)) {
            path[0] = _aggregator(token, Denominations.USD);
        } else if (_exists(token, Denominations.ETH)) {
            path[0] = _aggregator(token, Denominations.ETH);
            path[1] = _aggregator(Denominations.ETH, Denominations.USD);
        } else if (
            _exists(token, WRAPPED_BTC_TOKEN) &&
            _exists(WRAPPED_BTC_TOKEN, Denominations.USD)
        ) {
            path[0] = _aggregator(token, WRAPPED_BTC_TOKEN);
            path[1] = _aggregator(WRAPPED_BTC_TOKEN, Denominations.USD);
        }

        tier[0] = path;
        uint8[] memory decimals = new uint8[](2);

        if (tier[0][0] != address(0)) {
            decimals[0] = _aggregatorDecimals(tier[0][0]);
        }

        if (tier[0][1] != address(0)) {
            decimals[1] = _aggregatorDecimals(tier[0][1]);
        }

        if (tier[0][0] == address(0)) {
            address[] memory temp = tier[0];
            _resizeArray(temp, 0);
            tier[0] = temp;
        } else if (tier[0][1] == address(0)) {
            address[] memory temp = tier[0];
            _resizeArray(temp, 1);
            tier[0] = temp;
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

        return (AdapterType.CHAINLINK, Denominations.USD, tier, decimals);
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

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";

import {FeedRegistryInterface, ChainlinkAdapterInternal, ChainlinkAdapterStorage} from "./ChainlinkAdapterInternal.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    ERC165Base,
    SafeOwnable
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;

    constructor(
        FeedRegistryInterface _registry,
        address[] memory _addresses,
        address[] memory _mappings
    ) ChainlinkAdapterInternal(_registry, _addresses, _mappings) {
        _setOwner(msg.sender);
        _setSupportsInterface(type(IChainlinkAdapter).interfaceId, true);
    }

    /// @inheritdoc IOracleAdapter
    function canSupportPair(
        address tokenA,
        address tokenB
    ) external view returns (bool) {
        (address _tokenA, address _tokenB) = _mapAndSort(tokenA, tokenB);
        PricingPlan plan = _determinePricingPlan(_tokenA, _tokenB);
        return plan != PricingPlan.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function isPairAlreadySupported(
        address tokenA,
        address tokenB
    ) external view override(IOracleAdapter, OracleAdapter) returns (bool) {
        return _isPairAlreadySupported(tokenA, tokenB);
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address tokenIn,
        address tokenOut,
        bytes calldata
    ) external view returns (uint256) {
        (address mappedTokenIn, address mappedTokenOut) = _mapPair(
            tokenIn,
            tokenOut
        );

        PricingPlan plan = ChainlinkAdapterStorage.layout().planForPair[
            _keyForUnsortedPair(mappedTokenIn, mappedTokenOut)
        ];

        if (plan == PricingPlan.NONE) {
            revert Oracle__PairNotSupportedYet(tokenIn, tokenOut);
        } else if (plan <= PricingPlan.TOKEN_ETH_PAIR) {
            return _getDirectPrice(mappedTokenIn, mappedTokenOut, plan);
        } else if (plan <= PricingPlan.TOKEN_TO_ETH_TO_TOKEN_PAIR) {
            return _getPriceSameBase(mappedTokenIn, mappedTokenOut, plan);
        } else {
            return _getPriceDifferentBases(mappedTokenIn, mappedTokenOut, plan);
        }
    }

    /// @inheritdoc IChainlinkAdapter
    function planForPair(
        address tokenA,
        address tokenB
    ) external view returns (PricingPlan) {
        return _planForPair(tokenA, tokenB);
    }

    /// @inheritdoc IChainlinkAdapter
    function addMappings(
        address[] memory addresses,
        address[] memory mappings
    ) external onlyOwner {
        _addMappings(addresses, mappings);
    }

    /// @inheritdoc IChainlinkAdapter
    function mappedToken(address token) external view returns (address) {
        return _mappedToken(token);
    }

    /// @inheritdoc IChainlinkAdapter
    function maxDelay() external pure returns (uint32) {
        return MAX_DELAY;
    }

    /// @inheritdoc IChainlinkAdapter
    function feedRegistry() external view returns (address) {
        return address(FeedRegistry);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {SafeOwnable} from "@solidstate/contracts/access/ownable/SafeOwnable.sol";
import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";

import {FeedRegistryInterface, ChainlinkAdapterInternal} from "./ChainlinkAdapterInternal.sol";
import {IChainlinkAdapter} from "./IChainlinkAdapter.sol";
import {IOracleAdapter, OracleAdapter} from "./OracleAdapter.sol";

/// @notice derived from https://github.com/Mean-Finance/oracles
contract ChainlinkAdapter is
    ChainlinkAdapterInternal,
    IChainlinkAdapter,
    ERC165Base,
    SafeOwnable
{
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
        address _tokenA,
        address _tokenB
    ) external view returns (bool) {
        (address __tokenA, address __tokenB) = _mapAndSort(_tokenA, _tokenB);
        PricingPlan _plan = _determinePricingPlan(__tokenA, __tokenB);
        return _plan != PricingPlan.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function isPairAlreadySupported(
        address _tokenA,
        address _tokenB
    ) public view override(IOracleAdapter, OracleAdapter) returns (bool) {
        return planForPair(_tokenA, _tokenB) != PricingPlan.NONE;
    }

    /// @inheritdoc IOracleAdapter
    function quote(
        address _tokenIn,
        address _tokenOut,
        bytes calldata
    ) external view returns (uint256 _amountOut) {
        (address _mappedTokenIn, address _mappedTokenOut) = _mapPair(
            _tokenIn,
            _tokenOut
        );

        PricingPlan _plan = _planForPair[
            _keyForUnsortedPair(_mappedTokenIn, _mappedTokenOut)
        ];

        if (_plan == PricingPlan.NONE) {
            revert Oracle__PairNotSupportedYet(_tokenIn, _tokenOut);
        } else if (_plan <= PricingPlan.TOKEN_ETH_PAIR) {
            return _getDirectPrice(_mappedTokenIn, _mappedTokenOut, _plan);
        } else if (_plan <= PricingPlan.TOKEN_TO_ETH_TO_TOKEN_PAIR) {
            return _getPriceSameBase(_mappedTokenIn, _mappedTokenOut, _plan);
        } else {
            return
                _getPriceDifferentBases(_mappedTokenIn, _mappedTokenOut, _plan);
        }
    }

    /// @inheritdoc IChainlinkAdapter
    function planForPair(
        address _tokenA,
        address _tokenB
    ) public view returns (PricingPlan) {
        (address __tokenA, address __tokenB) = _mapAndSort(_tokenA, _tokenB);
        return _planForPair[_keyForSortedPair(__tokenA, __tokenB)];
    }

    /// @inheritdoc IChainlinkAdapter
    function addMappings(
        address[] memory _addresses,
        address[] memory _mappings
    ) external onlyOwner {
        _addMappings(_addresses, _mappings);
    }

    /// @inheritdoc IChainlinkAdapter
    function mappedToken(address _token) external view returns (address) {
        return _mappedToken(_token);
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

// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {OracleAdapterInternal} from "./OracleAdapterInternal.sol";
import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title Base oracle adapter implementation, which suppoprts access control multi-call and ERC165
/// @notice Most implementations of `IOracleAdapter` will have an internal function that is called in both
///         `addSupportForPairIfNeeded` and `addOrModifySupportForPair`. This oracle is now making this explicit, and
///         implementing these two functions. They remain virtual so that they can be overriden if needed.
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract OracleAdapter is
    IOracleAdapter,
    Multicall,
    OracleAdapterInternal
{
    /// @inheritdoc IOracleAdapter
    function isPairSupported(
        address tokenA,
        address tokenB
    ) external view virtual returns (bool);

    /// @inheritdoc IOracleAdapter
    function addOrModifySupportForPair(
        address tokenA,
        address tokenB
    ) external virtual {
        _addOrModifySupportForPair(tokenA, tokenB);
    }

    /// @inheritdoc IOracleAdapter
    function addSupportForPairIfNeeded(
        address tokenA,
        address tokenB
    ) external virtual {
        if (_isPairSupported(tokenA, tokenB))
            revert OracleAdapter__PairAlreadySupported(tokenA, tokenB);

        _addOrModifySupportForPair(tokenA, tokenB);
    }
}

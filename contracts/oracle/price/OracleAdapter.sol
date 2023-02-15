// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title Base oracle adapter implementation, which suppoprts access control multi-call and ERC165
/// @notice Most implementations of `IOracleAdapter` will have an internal function that is called in both
///         `addSupportForPairIfNeeded` and `addOrModifySupportForPair`. This oracle is now making this explicit, and
///         implementing these two functions. They remain virtual so that they can be overriden if needed.
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract OracleAdapter is
    ERC165BaseInternal,
    IOracleAdapter,
    Multicall
{
    constructor() {
        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IOracleAdapter).interfaceId, true);
        _setSupportsInterface(type(Multicall).interfaceId, true);
    }

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

    function _isPairSupported(
        address tokenA,
        address tokenB
    ) internal view virtual returns (bool);

    /// @notice Add or reconfigures the support for a given pair. This function will let the oracle take some actions
    ///         to configure the pair, in preparation for future quotes. Can be called many times in order to let the oracle
    ///         re-configure for a new context
    /// @dev Will revert if pair cannot be supported. tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    function _addOrModifySupportForPair(
        address tokenA,
        address tokenB
    ) internal virtual;
}

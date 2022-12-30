// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {IERC1155} from "@solidstate/contracts/interfaces/IERC1155.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IDiamondReadable} from "@solidstate/contracts/proxy/diamond/readable/IDiamondReadable.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {PoolStorage} from "./PoolStorage.sol";

/// @title Upgradeable proxy with centrally controlled Pool implementation
contract PoolProxy is Proxy, ERC165BaseInternal {
    using PoolStorage for PoolStorage.Layout;

    address private immutable DIAMOND;

    constructor(
        address diamond,
        address base,
        address underlying,
        address baseOracle,
        address underlyingOracle,
        uint256 strike,
        uint64 maturity,
        bool isCallPool
    ) {
        DIAMOND = diamond;
        OwnableStorage.layout().owner = msg.sender;

        {
            PoolStorage.Layout storage l = PoolStorage.layout();

            l.base = base;
            l.underlying = underlying;

            // ToDo : Add checks for oracle
            l.baseOracle = baseOracle;
            l.underlyingOracle = underlyingOracle;

            l.strike = strike;
            l.maturity = maturity;

            uint8 baseDecimals = IERC20Metadata(base).decimals();
            uint8 underlyingDecimals = IERC20Metadata(underlying).decimals();

            l.baseDecimals = baseDecimals;
            l.underlyingDecimals = underlyingDecimals;

            l.isCallPool = isCallPool;
        }

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IERC1155).interfaceId, true);
    }

    function _getImplementation() internal view override returns (address) {
        return IDiamondReadable(DIAMOND).facetAddress(msg.sig);
    }
}

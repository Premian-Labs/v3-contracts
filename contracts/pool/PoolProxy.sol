// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {IERC1155} from "@solidstate/contracts/interfaces/IERC1155.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IDiamondReadable} from "@solidstate/contracts/proxy/diamond/readable/IDiamondReadable.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {DoublyLinkedListUD60x18, DoublyLinkedList} from "../libraries/DoublyLinkedListUD60x18.sol";
import {PRBMathExtra} from "../libraries/PRBMathExtra.sol";

import {PoolStorage} from "./PoolStorage.sol";

/// @title Upgradeable proxy with centrally controlled Pool implementation
contract PoolProxy is Proxy, ERC165BaseInternal {
    using DoublyLinkedListUD60x18 for DoublyLinkedList.Bytes32List;
    using PoolStorage for PoolStorage.Layout;
    using PRBMathExtra for UD60x18;

    address private immutable DIAMOND;

    constructor(
        address diamond,
        address base,
        address quote,
        address oracleAdapter,
        UD60x18 strike,
        uint256 maturity,
        bool isCallPool
    ) {
        DIAMOND = diamond;
        OwnableStorage.layout().owner = msg.sender;

        {
            PoolStorage.Layout storage l = PoolStorage.layout();

            l.base = base;
            l.quote = quote;

            l.oracleAdapter = oracleAdapter;

            l.strike = strike;
            l.maturity = maturity;

            uint8 baseDecimals = IERC20Metadata(base).decimals();
            uint8 quoteDecimals = IERC20Metadata(quote).decimals();

            l.baseDecimals = baseDecimals;
            l.quoteDecimals = quoteDecimals;

            l.isCallPool = isCallPool;

            l.tickIndex.push(PoolStorage.MIN_TICK_PRICE);
            l.tickIndex.push(PoolStorage.MAX_TICK_PRICE);

            l.currentTick = PoolStorage.MIN_TICK_PRICE;
            l.marketPrice = PoolStorage.MIN_TICK_PRICE.intoUD50x28();
        }

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IERC1155).interfaceId, true);
    }

    function _getImplementation() internal view override returns (address) {
        return IDiamondReadable(DIAMOND).facetAddress(msg.sig);
    }
}

// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

import {UniswapV3AdapterStorage} from "./UniswapV3AdapterStorage.sol";

contract UniswapV3AdapterProxy is ERC165BaseInternal, ProxyUpgradeableOwnable {
    using UniswapV3AdapterStorage for UniswapV3AdapterStorage.Layout;

    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        UniswapV3AdapterStorage.Layout storage l = UniswapV3AdapterStorage
            .layout();

        l.gasPerCardinality = 22_250;
        l.gasCostToSupportPool = 30_000;

        l.feeTiers.push(500);
        l.feeTiers.push(3_000);
        l.feeTiers.push(10_000);

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(Multicall).interfaceId, true);
    }
}

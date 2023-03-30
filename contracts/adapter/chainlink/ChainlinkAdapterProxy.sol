// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity >=0.8.19;

import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

contract ChainlinkAdapterProxy is ERC165BaseInternal, ProxyUpgradeableOwnable {
    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(Multicall).interfaceId, true);
    }
}

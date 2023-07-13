// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";

import {ProxyUpgradeableOwnable} from "../proxy/ProxyUpgradeableOwnable.sol";

contract VxPremiaProxy is ProxyUpgradeableOwnable, ERC20MetadataInternal {
    constructor(address implementation) ProxyUpgradeableOwnable(implementation) {
        _setName("vxPremia");
        _setSymbol("vxPREMIA");
        _setDecimals(18);
    }
}

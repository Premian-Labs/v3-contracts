// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
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

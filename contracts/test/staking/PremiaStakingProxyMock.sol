// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC20MetadataInternal} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataInternal.sol";

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

contract PremiaStakingProxyMock is
    ProxyUpgradeableOwnable,
    ERC20MetadataInternal
{
    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        _setName("Staked Premia");
        _setSymbol("xPREMIA");
        _setDecimals(18);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

contract PremiaStakingProxyMock is ProxyUpgradeableOwnable {
    constructor(address implementation) ProxyUpgradeableOwnable(implementation) {
        ERC20MetadataStorage.Layout storage l = ERC20MetadataStorage.layout();

        l.name = "Staked Premia";
        l.symbol = "vxPREMIA";
        l.decimals = 18;
    }
}

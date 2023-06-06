// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";

import {IProxyUpgradeableOwnable} from "../proxy/IProxyUpgradeableOwnable.sol";
import {MiningPoolStorage} from "./MiningPoolStorage.sol";

contract MiningPoolProxy is Proxy {
    address private immutable PROXY;

    constructor(
        address proxy,
        address base,
        address quote,
        address priceRepository,
        address paymentSplitter,
        UD60x18 percentOfSpot,
        uint256 daysToExpiry,
        uint256 exerciseDuration,
        uint256 lockupDuration
    ) {
        PROXY = proxy;
        OwnableStorage.layout().owner = msg.sender;

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();

        l.base = base;
        l.quote = quote;
        l.priceRepository = priceRepository;
        l.paymentSplitter = paymentSplitter;
        l.percentOfSpot = percentOfSpot;
        l.daysToExpiry = daysToExpiry;
        l.exerciseDuration = exerciseDuration;
        l.lockupDuration = lockupDuration;
    }

    function _getImplementation() internal view override returns (address) {
        return IProxyUpgradeableOwnable(PROXY).getImplementation();
    }

    receive() external payable {}
}

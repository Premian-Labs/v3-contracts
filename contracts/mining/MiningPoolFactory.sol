// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {MiningPoolProxy} from "./MiningPoolProxy.sol";

contract MiningPoolFactory {
    address private immutable PROXY;

    constructor(address proxy) {
        PROXY = proxy;
    }

    function deployMiningPool(
        address base,
        address quote,
        address priceRepository,
        address paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 expiryDuration,
        uint256 exerciseDuration,
        uint256 lockupDuration
    ) external returns (address) {
        MiningPoolProxy miningPoolProxy = new MiningPoolProxy(
            PROXY,
            base,
            quote,
            priceRepository,
            paymentSplitter,
            discount,
            penalty,
            expiryDuration,
            exerciseDuration,
            lockupDuration
        );

        // TODO: store mining pool address
        // TODO: emit event

        return address(miningPoolProxy);
    }
}

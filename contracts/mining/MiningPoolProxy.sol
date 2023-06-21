// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {IProxyUpgradeableOwnable} from "../proxy/IProxyUpgradeableOwnable.sol";
import {MiningPoolStorage} from "./MiningPoolStorage.sol";

contract MiningPoolProxy is Proxy {
    address private immutable PROXY;

    constructor(
        address proxy,
        address base,
        address quote,
        address underwriter,
        address priceRepository,
        address paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 expiryDuration, // TODO;
        uint256 exerciseDuration,
        uint256 lockupDuration
    ) {
        PROXY = proxy;
        OwnableStorage.layout().owner = msg.sender;

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();

        l.baseDecimals = IERC20Metadata(base).decimals();
        l.quoteDecimals = IERC20Metadata(quote).decimals();

        l.base = base;
        l.quote = quote;

        l.underwriter = underwriter;

        l.priceRepository = priceRepository;
        l.paymentSplitter = paymentSplitter;

        l.discount = discount;
        l.penalty = penalty;

        l.expiryDuration = expiryDuration;
        l.exerciseDuration = exerciseDuration;
        l.lockupDuration = lockupDuration;
    }

    function _getImplementation() internal view override returns (address) {
        return IProxyUpgradeableOwnable(PROXY).getImplementation();
    }

    receive() external payable {}
}

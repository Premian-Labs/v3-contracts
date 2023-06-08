// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {ONE} from "../libraries/Constants.sol";

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
        UD60x18 discount,
        UD60x18 penalty,
        uint256 expiryDuration,
        uint256 exerciseDuration,
        uint256 lockupDuration
    ) {
        PROXY = proxy;
        OwnableStorage.layout().owner = msg.sender;

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();

        // TODO: custom error messages
        if (base == address(0) || quote == address(0) || priceRepository == address(0) || paymentSplitter == address(0))
            revert();
        // TODO: custom error messages
        if (discount > ONE || penalty > ONE) revert();
        // TODO: custom error messages
        if (expiryDuration == 0 || exerciseDuration == 0 || lockupDuration == 0) revert();

        l.baseDecimals = IERC20Metadata(base).decimals();
        l.quoteDecimals = IERC20Metadata(quote).decimals();

        l.base = base;
        l.quote = quote;

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

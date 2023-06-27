// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {IProxyUpgradeableOwnable} from "../../proxy/IProxyUpgradeableOwnable.sol";
import {OptionRewardStorage} from "./OptionRewardStorage.sol";
import {IOptionReward} from "./IOptionReward.sol";
import {IOptionPS} from "../optionPS/IOptionPS.sol";

contract OptionRewardProxy is Proxy {
    address private immutable PROXY;

    constructor(
        address proxy,
        IOptionPS option,
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

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        l.option = option;

        // ToDo : Validate option contract
        (address base, address quote, bool isCall) = option.getSettings();
        if (!isCall) revert IOptionReward.OptionReward__NotCallOption(address(option));

        l.base = base;
        l.quote = quote;

        l.baseDecimals = IERC20Metadata(base).decimals();
        l.quoteDecimals = IERC20Metadata(quote).decimals();

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

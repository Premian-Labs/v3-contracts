// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {IOracleAdapter} from "../../adapter/IOracleAdapter.sol";
import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {OptionRewardStorage} from "./OptionRewardStorage.sol";
import {IOptionReward} from "./IOptionReward.sol";
import {IOptionPS} from "../optionPS/IOptionPS.sol";
import {IPaymentSplitter} from "../IPaymentSplitter.sol";

contract OptionRewardProxy is Proxy {
    IProxyManager private immutable MANAGER;

    constructor(
        IProxyManager manager,
        IOptionPS option,
        IOracleAdapter oracleAdapter,
        IPaymentSplitter paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 optionDuration,
        uint256 lockupDuration,
        uint256 claimDuration
    ) {
        MANAGER = manager;
        OwnableStorage.layout().owner = msg.sender;

        OptionRewardStorage.Layout storage l = OptionRewardStorage.layout();

        l.option = option;

        (address base, address quote, bool isCall) = option.getSettings();
        if (!isCall) revert IOptionReward.OptionReward__NotCallOption(address(option));

        l.base = base;
        l.quote = quote;

        l.baseDecimals = IERC20Metadata(base).decimals();
        l.quoteDecimals = IERC20Metadata(quote).decimals();

        l.optionDuration = optionDuration;
        l.oracleAdapter = oracleAdapter;
        l.paymentSplitter = paymentSplitter;

        l.discount = discount;
        l.penalty = penalty;
        l.lockupDuration = lockupDuration;
        l.claimDuration = claimDuration;
    }

    function _getImplementation() internal view override returns (address) {
        return MANAGER.getManagedProxyImplementation();
    }

    receive() external payable {}
}

// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOptionPS} from "../optionPS/IOptionPS.sol";
import {IProxyManager} from "../../proxy/IProxyManager.sol";

interface IOptionRewardFactory is IProxyManager {
    event ProxyDeployed(
        IOptionPS indexed option,
        address oracleAdapter,
        address paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 optionDuration,
        uint256 lockupDuration,
        uint256 claimDuration,
        address proxy
    );

    struct OptionRewardArgs {
        IOptionPS option;
        address oracleAdapter;
        address paymentSplitter;
        UD60x18 discount;
        UD60x18 penalty;
        uint256 optionDuration;
        uint256 lockupDuration;
        uint256 claimDuration;
    }

    function isProxyDeployed(address proxy) external view returns (bool);

    function getProxyAddress(OptionRewardArgs calldata args) external view returns (address, bool);

    function deployProxy(OptionRewardArgs calldata args) external returns (address);
}

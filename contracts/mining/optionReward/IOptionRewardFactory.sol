// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOracleAdapter} from "../../adapter/IOracleAdapter.sol";
import {IOptionPS} from "../optionPS/IOptionPS.sol";
import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {IPaymentSplitter} from "../IPaymentSplitter.sol";

interface IOptionRewardFactory is IProxyManager {
    error OptionRewardFactory__ProxyAlreadyDeployed(address proxy);

    event ProxyDeployed(
        IOptionPS indexed option,
        IOracleAdapter oracleAdapter,
        IPaymentSplitter paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 optionDuration,
        uint256 lockupDuration,
        uint256 claimDuration,
        UD60x18 fee,
        address feeReceiver,
        address proxy
    );

    struct OptionRewardArgs {
        IOptionPS option;
        IOracleAdapter oracleAdapter;
        IPaymentSplitter paymentSplitter;
        UD60x18 discount;
        UD60x18 penalty;
        uint256 optionDuration;
        uint256 lockupDuration;
        uint256 claimDuration;
    }

    struct OptionRewardKey {
        IOptionPS option;
        IOracleAdapter oracleAdapter;
        IPaymentSplitter paymentSplitter;
        UD60x18 discount;
        UD60x18 penalty;
        uint256 optionDuration;
        uint256 lockupDuration;
        uint256 claimDuration;
        UD60x18 fee;
        address feeReceiver;
    }

    /// @notice Returns the default fee
    function getDefaultFee() external view returns (UD60x18);

    /// @notice Returns the default fee receiver
    function getDefaultFeeReceiver() external view returns (address);

    /// @notice Returns true if `proxy` is a deployed proxy
    function isProxyDeployed(address proxy) external view returns (bool);

    /// @notice Returns the proxy address and whether it is deployed
    function getProxyAddress(OptionRewardKey calldata args) external view returns (address, bool);

    /// @notice Deploys a new proxy
    function deployProxy(OptionRewardArgs calldata args) external returns (address);
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOptionPS} from "../optionPS/IOptionPS.sol";
import {IProxyManager} from "../../proxy/IProxyManager.sol";

interface IOptionRewardFactory is IProxyManager {
    event ProxyDeployed(
        IOptionPS indexed option,
        address priceRepository,
        address paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 optionDuration,
        uint256 lockupDuration,
        address proxy
    );

    struct OptionRewardArgs {
        IOptionPS option;
        address priceRepository;
        address paymentSplitter;
        UD60x18 discount;
        UD60x18 penalty;
        uint256 optionDuration;
        uint256 lockupDuration;
    }

    function isProxyDeployed(address proxy) external view returns (bool);

    function getProxyAddress(OptionRewardArgs calldata args) external view returns (address, bool);

    function deployProxy(OptionRewardArgs calldata args) external returns (address);
}

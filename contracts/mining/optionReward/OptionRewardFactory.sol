// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {IOptionRewardFactory} from "./IOptionRewardFactory.sol";
import {OptionRewardProxy} from "./OptionRewardProxy.sol";
import {OptionRewardFactoryStorage} from "./OptionRewardFactoryStorage.sol";

import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {ProxyManager} from "../../proxy/ProxyManager.sol";

contract OptionRewardFactory is IOptionRewardFactory, ProxyManager, ReentrancyGuard {
    using OptionRewardFactoryStorage for OptionRewardArgs;
    using OptionRewardFactoryStorage for OptionRewardFactoryStorage.Layout;

    function isProxyDeployed(address proxy) external view returns (bool) {
        return OptionRewardFactoryStorage.layout().isProxyDeployed[proxy];
    }

    function getProxyAddress(OptionRewardArgs calldata args) external view returns (address proxy, bool) {
        OptionRewardFactoryStorage.Layout storage l = OptionRewardFactoryStorage.layout();
        proxy = l.proxyByKey[args.keyHash()];
        return (proxy, l.isProxyDeployed[proxy]);
    }

    function deployProxy(OptionRewardArgs calldata args) external nonReentrant returns (address proxy) {
        proxy = address(
            new OptionRewardProxy(
                IProxyManager(address(this)),
                args.option,
                args.oracleAdapter,
                args.paymentSplitter,
                args.discount,
                args.penalty,
                args.optionDuration,
                args.lockupDuration,
                args.claimDuration
            )
        );

        OptionRewardFactoryStorage.Layout storage l = OptionRewardFactoryStorage.layout();

        l.proxyByKey[args.keyHash()] = proxy;
        l.isProxyDeployed[proxy] = true;

        emit ProxyDeployed(
            args.option,
            args.oracleAdapter,
            args.paymentSplitter,
            args.discount,
            args.penalty,
            args.optionDuration,
            args.lockupDuration,
            args.claimDuration,
            proxy
        );
    }
}

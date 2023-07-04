// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IOptionRewardFactory} from "./IOptionRewardFactory.sol";
import {OptionRewardProxy} from "./OptionRewardProxy.sol";
import {OptionRewardFactoryStorage} from "./OptionRewardFactoryStorage.sol";

import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {ProxyManager} from "../../proxy/ProxyManager.sol";

contract OptionRewardFactory is IOptionRewardFactory, ProxyManager {
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

    function deployProxy(OptionRewardArgs calldata args) external returns (address proxy) {
        proxy = address(
            new OptionRewardProxy(
                IProxyManager(address(this)),
                args.option,
                args.priceRepository,
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
            args.priceRepository,
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

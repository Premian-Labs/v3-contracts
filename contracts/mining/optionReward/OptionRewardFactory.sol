// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IOptionRewardFactory} from "./IOptionRewardFactory.sol";
import {OptionRewardProxy} from "./OptionRewardProxy.sol";
import {OptionRewardFactoryStorage} from "./OptionRewardFactoryStorage.sol";

contract OptionRewardFactory is IOptionRewardFactory {
    using OptionRewardFactoryStorage for OptionRewardArgs;
    using OptionRewardFactoryStorage for OptionRewardFactoryStorage.Layout;

    address private immutable PROXY;

    constructor(address proxy) {
        PROXY = proxy;
    }

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
                PROXY,
                args.option,
                args.priceRepository,
                args.paymentSplitter,
                args.discount,
                args.penalty,
                args.expiryDuration,
                args.exerciseDuration,
                args.lockupDuration
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
            args.expiryDuration,
            args.exerciseDuration,
            args.lockupDuration,
            proxy
        );
    }
}

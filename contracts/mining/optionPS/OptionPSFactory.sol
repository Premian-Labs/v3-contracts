// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {IOptionPSFactory} from "./IOptionPSFactory.sol";
import {OptionPSProxy} from "./OptionPSProxy.sol";
import {OptionPSFactoryStorage} from "./OptionPSFactoryStorage.sol";
import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {ProxyManager} from "../../proxy/ProxyManager.sol";

contract OptionPSFactory is IOptionPSFactory, ProxyManager, ReentrancyGuard {
    using OptionPSFactoryStorage for OptionPSArgs;
    using OptionPSFactoryStorage for OptionPSFactoryStorage.Layout;

    /// @inheritdoc IOptionPSFactory
    function isProxyDeployed(address proxy) external view returns (bool) {
        return OptionPSFactoryStorage.layout().isProxyDeployed[proxy];
    }

    /// @inheritdoc IOptionPSFactory
    function getProxyAddress(OptionPSArgs calldata args) external view returns (address proxy, bool isDeployed) {
        OptionPSFactoryStorage.Layout storage l = OptionPSFactoryStorage.layout();
        proxy = l.proxyByKey[args.keyHash()];
        return (proxy, l.isProxyDeployed[proxy]);
    }

    /// @inheritdoc IOptionPSFactory
    function deployProxy(OptionPSArgs calldata args) external nonReentrant returns (address proxy) {
        proxy = address(new OptionPSProxy(IProxyManager(address(this)), args.base, args.quote, args.isCall));

        OptionPSFactoryStorage.Layout storage l = OptionPSFactoryStorage.layout();

        l.proxyByKey[args.keyHash()] = proxy;
        l.isProxyDeployed[proxy] = true;

        emit ProxyDeployed(args.base, args.quote, args.isCall, proxy);
    }
}

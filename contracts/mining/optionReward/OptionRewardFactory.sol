// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";

import {IOptionRewardFactory} from "./IOptionRewardFactory.sol";
import {OptionRewardProxy} from "./OptionRewardProxy.sol";
import {OptionRewardFactoryStorage} from "./OptionRewardFactoryStorage.sol";

import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {ProxyManager} from "../../proxy/ProxyManager.sol";
import {IOracleAdapter} from "../../adapter/IOracleAdapter.sol";

contract OptionRewardFactory is IOptionRewardFactory, ProxyManager, ReentrancyGuard {
    using OptionRewardFactoryStorage for OptionRewardKey;
    using OptionRewardFactoryStorage for OptionRewardFactoryStorage.Layout;

    UD60x18 internal immutable DEFAULT_FEE;
    address internal immutable DEFAULT_FEE_RECEIVER;

    constructor(UD60x18 defaultFee, address defaultFeeReceiver) {
        DEFAULT_FEE = defaultFee;
        DEFAULT_FEE_RECEIVER = defaultFeeReceiver;
    }

    /// @inheritdoc IOptionRewardFactory
    function getDefaultFee() external view returns (UD60x18) {
        return DEFAULT_FEE;
    }

    /// @inheritdoc IOptionRewardFactory
    function getDefaultFeeReceiver() external view returns (address) {
        return DEFAULT_FEE_RECEIVER;
    }

    /// @inheritdoc IOptionRewardFactory
    function isProxyDeployed(address proxy) external view returns (bool) {
        return OptionRewardFactoryStorage.layout().isProxyDeployed[proxy];
    }

    /// @inheritdoc IOptionRewardFactory
    function getProxyAddress(OptionRewardKey calldata key) external view returns (address proxy, bool) {
        OptionRewardFactoryStorage.Layout storage l = OptionRewardFactoryStorage.layout();
        proxy = l.proxyByKey[key.keyHash()];
        return (proxy, l.isProxyDeployed[proxy]);
    }

    /// @notice Deploys a new proxy, with ability to override fee and feeReceiver (Only callable by owner)
    function deployProxy(OptionRewardKey calldata key) external onlyOwner returns (address proxy) {
        return _deployProxy(key);
    }

    /// @inheritdoc IOptionRewardFactory
    function deployProxy(OptionRewardArgs calldata args) external nonReentrant returns (address proxy) {
        return
            _deployProxy(
                OptionRewardKey(
                    args.option,
                    args.oracleAdapter,
                    args.paymentSplitter,
                    args.percentOfSpot,
                    args.penalty,
                    args.optionDuration,
                    args.lockupDuration,
                    args.claimDuration,
                    DEFAULT_FEE,
                    DEFAULT_FEE_RECEIVER
                )
            );
    }

    function _deployProxy(OptionRewardKey memory key) internal returns (address proxy) {
        OptionRewardFactoryStorage.Layout storage l = OptionRewardFactoryStorage.layout();

        bytes32 keyHash = key.keyHash();
        if (l.proxyByKey[keyHash] != address(0))
            revert OptionRewardFactory__ProxyAlreadyDeployed(l.proxyByKey[keyHash]);

        proxy = address(
            new OptionRewardProxy(
                IProxyManager(address(this)),
                key.option,
                key.oracleAdapter,
                key.paymentSplitter,
                key.percentOfSpot,
                key.penalty,
                key.optionDuration,
                key.lockupDuration,
                key.claimDuration,
                key.fee,
                key.feeReceiver
            )
        );

        l.proxyByKey[keyHash] = proxy;
        l.isProxyDeployed[proxy] = true;

        emit ProxyDeployed(
            key.option,
            key.oracleAdapter,
            key.paymentSplitter,
            key.percentOfSpot,
            key.penalty,
            key.optionDuration,
            key.lockupDuration,
            key.claimDuration,
            key.fee,
            key.feeReceiver,
            proxy
        );

        {
            (address base, address quote, ) = key.option.getSettings();

            (
                IOracleAdapter.AdapterType baseAdapterType,
                address[][] memory basePath,
                uint8[] memory basePathDecimals
            ) = IOracleAdapter(key.oracleAdapter).describePricingPath(base);

            (
                IOracleAdapter.AdapterType quoteAdapterType,
                address[][] memory quotePath,
                uint8[] memory quotePathDecimals
            ) = IOracleAdapter(key.oracleAdapter).describePricingPath(quote);

            emit PricingPath(
                address(key.option),
                basePath,
                basePathDecimals,
                baseAdapterType,
                quotePath,
                quotePathDecimals,
                quoteAdapterType
            );
        }
    }
}

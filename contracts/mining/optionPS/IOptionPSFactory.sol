// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {IProxyManager} from "../../proxy/IProxyManager.sol";

interface IOptionPSFactory is IProxyManager {
    event ProxyDeployed(address indexed base, address indexed quote, bool isCall, address proxy);

    struct OptionPSArgs {
        address base;
        address quote;
        bool isCall;
    }

    /// @notice Return whether `proxy` is a deployed proxy
    function isProxyDeployed(address proxy) external view returns (bool);

    /// @notice Return the proxy address and whether it is deployed
    /// @param args The arguments used to deploy the proxy
    /// @return proxy The proxy address
    /// @return isDeployed Whether the proxy is deployed
    function getProxyAddress(OptionPSArgs calldata args) external view returns (address proxy, bool isDeployed);

    /// @notice Deploy a new proxy
    function deployProxy(OptionPSArgs calldata args) external returns (address);
}

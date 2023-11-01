// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {IProxyManager} from "../../proxy/IProxyManager.sol";

import {DualMiningStorage} from "./DualMiningStorage.sol";

contract DualMiningProxy is Proxy {
    IProxyManager private immutable MANAGER;

    constructor(IProxyManager manager, address vault, address rewardToken, UD60x18 rewardsPerYear) {
        MANAGER = manager;
        OwnableStorage.layout().owner = msg.sender;

        DualMiningStorage.Layout storage l = DualMiningStorage.layout();

        l.vault = vault;
        l.rewardsPerYear = rewardsPerYear;
        l.rewardToken = rewardToken;
        l.rewardTokenDecimals = IERC20Metadata(rewardToken).decimals();
    }

    /// @inheritdoc Proxy
    function _getImplementation() internal view override returns (address) {
        return MANAGER.getManagedProxyImplementation();
    }

    /// @notice get address of implementation contract
    /// @return implementation address
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }
}

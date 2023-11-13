// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {DualMiningStorage} from "./DualMiningStorage.sol";
import {DualMiningManager} from "./DualMiningManager.sol";

contract DualMiningProxy is Proxy, OwnableInternal {
    DualMiningManager private immutable MANAGER;

    constructor(DualMiningManager manager, address vault, address rewardToken, UD60x18 rewardsPerYear) {
        MANAGER = manager;
        // Set to deployer, just in case `l.owner` is directly used somewhere, but this should not be used as we override `_owner()`
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

    function _owner() internal view override returns (address) {
        return MANAGER.owner();
    }
}

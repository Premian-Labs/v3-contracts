// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {ProxyUpgradeableOwnable} from "../../proxy/ProxyUpgradeableOwnable.sol";

import {ChainlinkAdapterInternal} from "./ChainlinkAdapterInternal.sol";
import {ChainlinkAdapterStorage} from "./ChainlinkAdapterStorage.sol";

contract ChainlinkAdapterProxy is
    ChainlinkAdapterInternal,
    ERC165BaseInternal,
    ProxyUpgradeableOwnable
{
    using ChainlinkAdapterStorage for ChainlinkAdapterStorage.Layout;

    constructor(
        address implementation,
        address wrappedNativeToken,
        address wrappedBTCToken,
        FeedMappingArgs[] memory feedMappingArgs
    ) ProxyUpgradeableOwnable(implementation) {
        ChainlinkAdapterStorage.Layout storage l = ChainlinkAdapterStorage
            .layout();

        l.wrappedNativeToken = wrappedNativeToken;
        l.wrappedBTCToken = wrappedBTCToken;

        _batchRegisterFeedMappings(feedMappingArgs);

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(Multicall).interfaceId, true);
    }
}

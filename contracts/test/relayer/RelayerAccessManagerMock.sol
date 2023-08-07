// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {RelayerAccessManager} from "../../relayer/RelayerAccessManager.sol";

contract RelayerAccessManagerMock is RelayerAccessManager {
    function __revertIfNotWhitelistedRelayer(address relayer) external view {
        _revertIfNotWhitelistedRelayer(relayer);
    }
}

// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {IERC1155} from "@solidstate/contracts/interfaces/IERC1155.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {Proxy} from "@solidstate/contracts/proxy/Proxy.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";

import {IProxyManager} from "../../proxy/IProxyManager.sol";
import {OptionPSStorage} from "./OptionPSStorage.sol";
import {OptionPSFactory} from "./OptionPSFactory.sol";

contract OptionPSProxy is Proxy, ERC165BaseInternal {
    IProxyManager private immutable MANAGER;

    constructor(IProxyManager manager, address base, address quote, bool isCall) {
        MANAGER = manager;
        OwnableStorage.layout().owner = msg.sender;

        OptionPSStorage.Layout storage l = OptionPSStorage.layout();

        l.isCall = isCall;
        l.baseDecimals = IERC20Metadata(base).decimals();
        l.quoteDecimals = IERC20Metadata(quote).decimals();

        l.base = base;
        l.quote = quote;

        _setSupportsInterface(type(IERC165).interfaceId, true);
        _setSupportsInterface(type(IERC1155).interfaceId, true);
    }

    function _getImplementation() internal view override returns (address) {
        return MANAGER.getManagedProxyImplementation();
    }

    receive() external payable {}
}

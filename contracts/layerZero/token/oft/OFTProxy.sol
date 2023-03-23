// SPDX-License-Identifier: MIT

pragma solidity >=0.8.19;

import {ERC165BaseInternal} from "@solidstate/contracts/introspection/ERC165/base/ERC165BaseInternal.sol";
import {IERC165} from "@solidstate/contracts/interfaces/IERC165.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {ProxyUpgradeableOwnable} from "../../../proxy/ProxyUpgradeableOwnable.sol";
import {IOFT} from "./IOFT.sol";
import {IOFTCore} from "./IOFTCore.sol";

contract OFTProxy is ProxyUpgradeableOwnable, ERC165BaseInternal {
    constructor(
        address implementation
    ) ProxyUpgradeableOwnable(implementation) {
        {
            _setSupportsInterface(type(IERC165).interfaceId, true);
            _setSupportsInterface(type(IERC20).interfaceId, true);
            _setSupportsInterface(type(IOFTCore).interfaceId, true);
            _setSupportsInterface(type(IOFT).interfaceId, true);
        }
    }
}

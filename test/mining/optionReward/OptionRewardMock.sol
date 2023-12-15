// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ERC1155Base} from "@solidstate/contracts/token/ERC1155/base/ERC1155Base.sol";

contract OptionRewardMock is ERC1155Base, ERC165Base {
    address internal immutable BASE;

    constructor(address base) {
        BASE = base;
    }

    function underwrite(address longReceiver, UD60x18 contractSize) external {
        IERC20(BASE).transferFrom(msg.sender, address(this), contractSize.unwrap());
        _mint(longReceiver, 0, contractSize.unwrap(), "");
    }
}

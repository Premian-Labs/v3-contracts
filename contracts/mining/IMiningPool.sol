// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IERC1155Base} from "@solidstate/contracts/token/ERC1155/base/IERC1155Base.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";

interface IMiningPool is IERC1155Base, IERC1155Enumerable {
    enum TokenType {
        LONG,
        SHORT
    }

    error MiningPool__OperatorNotAuthorized(address sender);

    function writeFrom(address underwriter, address longReceiver, uint256 size) external;

    function exercise() external;

    function settle() external;
}

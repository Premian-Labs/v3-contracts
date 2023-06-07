// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC1155Base} from "@solidstate/contracts/token/ERC1155/base/IERC1155Base.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";

interface IMiningPool is IERC1155Base, IERC1155Enumerable {
    enum TokenType {
        LONG,
        SHORT
    }

    error MiningPool__OperatorNotAuthorized(address sender);

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 contractSize,
        int256 strike,
        uint64 maturity
    );

    function writeFrom(address underwriter, address longReceiver, UD60x18 contractSize) external;

    function exercise() external;

    function settle() external;
}

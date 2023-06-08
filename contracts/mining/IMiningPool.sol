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

    error MiningPool__LockupPeriodNotExpired(uint256 lockupStart, uint256 lockupEnd);
    error MiningPool__OperatorNotAuthorized(address sender);
    error MiningPool__OptionNotExpired(uint256 maturity);
    error MiningPool__OptionOutTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error MiningPool__TokenTypeNotLong();

    event Exercise(address indexed holder, UD60x18 contractSize, UD60x18 exerciseValue, UD60x18 settlementPrice);

    event WriteFrom(address indexed underwriter, address indexed longReceiver, UD60x18 contractSize);

    function writeFrom(address underwriter, address longReceiver, UD60x18 contractSize) external;

    function exercise(uint256 longTokenId, UD60x18 contractSize) external;

    function settle() external;
}

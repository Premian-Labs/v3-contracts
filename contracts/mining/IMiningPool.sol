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

    error MiningPool__LockupNotExpired(uint256 lockupStart, uint256 lockupEnd);
    error MiningPool__UnderwriterNotAuthorized(address sender);
    error MiningPool__OptionNotExpired(uint256 maturity);
    error MiningPool__OptionInTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error MiningPool__OptionOutTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error MiningPool__TokenTypeNotLong();
    error MiningPool__TokenTypeNotShort();

    event Exercise(
        address indexed user,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 exerciseCost,
        UD60x18 settlementPrice,
        UD60x18 strike,
        uint64 maturity
    );

    event Settle(address indexed user, UD60x18 contractSize, UD60x18 settlementPrice, UD60x18 strike, uint64 maturity);

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 contractSize,
        UD60x18 strike,
        uint64 maturity
    );

    /// @notice Underwrite an option by depositing collateral - only `underwriter` may call this function
    /// @param longReceiver address of long token receiver
    /// @param contractSize number of long tokens to mint (18 decimals)
    function writeFrom(address longReceiver, UD60x18 contractSize) external;

    /// @notice Exercises the long options held by the caller.
    /// @param longTokenId The ID of the long token to exercise
    /// @param contractSize number of long tokens to exercise (18 decimals)
    function exercise(uint256 longTokenId, UD60x18 contractSize) external;

    /// @notice Settles the short options held by the caller.
    /// @param shortTokenId The ID of the short token to settle
    /// @param contractSize number of short tokens to settle (18 decimals)
    function settle(uint256 shortTokenId, UD60x18 contractSize) external;
}

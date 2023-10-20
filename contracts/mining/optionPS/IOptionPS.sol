// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC1155Base} from "@solidstate/contracts/token/ERC1155/base/IERC1155Base.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";

interface IOptionPS is IERC1155Base, IERC1155Enumerable {
    enum TokenType {
        Long,
        Short,
        LongExercised
    }

    error OptionPS__OptionMaturityNot8UTC(uint256 maturity);
    error OptionPS__OptionExpired(uint256 maturity);
    error OptionPS__OptionNotExpired(uint256 maturity);
    error OptionPS__StrikeNotMultipleOfStrikeInterval(UD60x18 strike, UD60x18 strikeInterval);

    event Exercise(
        address indexed user,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize,
        UD60x18 exerciseCost,
        UD60x18 fee
    );

    event CancelExercise(
        address indexed user,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize,
        UD60x18 exerciseCostRefunded
    );

    event SettleLong(
        address indexed user,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize,
        UD60x18 exerciseValue
    );

    event SettleShort(
        address indexed user,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize,
        UD60x18 collateralAmount,
        UD60x18 exerciseTokenAmount
    );

    event Underwrite(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 contractSize
    );

    event Annihilate(address indexed annihilator, UD60x18 strike, uint256 maturity, UD60x18 contractSize);

    /// @notice Returns the pair infos for this option
    function getSettings() external view returns (address base, address quote, bool isCall);

    /// @notice Underwrite an option by depositing collateral
    /// @param strike the option strike price (18 decimals)
    /// @param longReceiver the address that will receive the long tokens
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of long tokens to mint (18 decimals)
    function underwrite(UD60x18 strike, uint64 maturity, address longReceiver, UD60x18 contractSize) external;

    /// @notice Burn longs and shorts, to recover collateral of the option
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of contracts to annihilate (18 decimals)
    function annihilate(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;

    /// @notice Returns the amount of `exerciseToken` to pay to exercise the given amount of contracts
    /// @param strike the option strike price (18 decimals)
    /// @param contractSize number of long tokens to exercise (18 decimals)
    /// @return totalExerciseCost the total amount of `exerciseToken` to pay, including fee (exerciseToken decimals)
    /// @return fee the amount of `exerciseToken` to pay as fee (exerciseToken decimals)
    function getExerciseCost(
        UD60x18 strike,
        UD60x18 contractSize
    ) external view returns (uint256 totalExerciseCost, uint256 fee);

    /// @notice Returns the amount of collateral that would be received for a given amount of long tokens
    /// @param strike the option strike price (18 decimals)
    /// @param contractSize number of long tokens to exercise (18 decimals)
    /// @return the amount of collateral (collateral decimals)
    function getExerciseValue(UD60x18 strike, UD60x18 contractSize) external view returns (uint256);

    /// @notice Pay the exercise cost for a given amount contracts. The exercise value will be claimable after maturity.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize amount of long tokens to exercise (18 decimals)
    function exercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;

    /// @notice Cancel an exercise before maturity, and recover the `exerciseToken` paid. (The fee paid during `exercise` is not recovered.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize amount of long tokens for which cancel exercise (18 decimals)
    function cancelExercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external;

    /// @notice Settle the exercised long options held by the caller.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of long tokens to settle (18 decimals)
    /// @return exerciseValue the amount of tokens transferred to the caller
    function settleLong(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external returns (uint256 exerciseValue);

    /// @notice Settles the short options held by the caller.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of short tokens to settle (18 decimals)
    /// @return collateralAmount the amount of collateral transferred to the caller (base for calls, quote for puts)
    /// @return exerciseTokenAmount the amount of exerciseToken transferred to the caller (quote for calls, base for puts)
    function settleShort(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external returns (uint256 collateralAmount, uint256 exerciseTokenAmount);

    /// @notice Returns the list of existing tokenIds with non zero balance
    /// @return tokenIds The list of existing tokenIds
    function getTokenIds() external view returns (uint256[] memory);
}

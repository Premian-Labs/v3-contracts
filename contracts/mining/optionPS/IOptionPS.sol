// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {IERC1155Base} from "@solidstate/contracts/token/ERC1155/base/IERC1155Base.sol";
import {IERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/IERC1155Enumerable.sol";

interface IOptionPS is IERC1155Base, IERC1155Enumerable {
    enum TokenType {
        LONG,
        SHORT
    }

    error OptionPS__ExercisePeriodEnded(uint256 maturity, uint256 exercisePeriodEnd);
    error OptionPS__ExercisePeriodNotEnded(uint256 maturity, uint256 exercisePeriodEnd);
    error OptionPS__OptionMaturityNot8UTC(uint256 maturity);
    error OptionPS__OptionNotExpired(uint256 maturity);
    error OptionPS__OptionOutTheMoney(UD60x18 settlementPrice, UD60x18 strike);
    error OptionPS__PriceIsStale(uint256 blockTimestamp, uint256 timestamp);
    error OptionPS__PriceIsZero();
    error OptionPS__StrikeNotMultipleOfStrikeInterval(UD60x18 strike, UD60x18 strikeInterval);

    event Exercise(
        address indexed user,
        UD60x18 contractSize,
        UD60x18 exerciseValue,
        UD60x18 exerciseCost,
        UD60x18 strike,
        uint256 maturity
    );

    event Settle(
        address indexed user,
        UD60x18 contractSize,
        UD60x18 strike,
        uint256 maturity,
        UD60x18 collateralLeft,
        UD60x18 exerciseShare
    );

    event Underwrite(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 contractSize,
        UD60x18 strike,
        uint256 maturity
    );

    event Annihilate(address indexed annihilator, UD60x18 contractSize, UD60x18 strike, uint256 maturity);

    function getSettings() external view returns (address base, address quote, bool isCall);

    function getExerciseDuration() external pure returns (uint256);

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

    /// @notice Exercises the long options held by the caller.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of long tokens to exercise (18 decimals)
    /// @return exerciseValue the amount of tokens transferred to the caller
    function exercise(UD60x18 strike, uint64 maturity, UD60x18 contractSize) external returns (uint256 exerciseValue);

    /// @notice Settles the short options held by the caller.
    /// @param strike the option strike price (18 decimals)
    /// @param maturity the option maturity timestamp
    /// @param contractSize number of short tokens to settle (18 decimals)
    /// @return baseAmount the amount of base tokens transferred to the caller
    /// @return quoteAmount the amount of quote tokens transferred to the caller
    function settle(
        UD60x18 strike,
        uint64 maturity,
        UD60x18 contractSize
    ) external returns (uint256 baseAmount, uint256 quoteAmount);
}

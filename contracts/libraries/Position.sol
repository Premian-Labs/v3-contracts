// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Math} from "@solidstate/contracts/utils/Math.sol";
import {UintUtils} from "@solidstate/contracts/utils/UintUtils.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {UD60x18} from "../libraries/prbMath/UD60x18.sol";

import {IPosition} from "./IPosition.sol";
import {Pricing} from "./Pricing.sol";

/// @notice Keeps track of LP positions
///         Stores the lower and upper Ticks of a user's range order, and tracks the pro-rata exposure of the order.
library Position {
    using Math for int256;
    using Position for Position.Key;
    using Position for Position.OrderType;
    using UintUtils for uint256;
    using SafeCast for uint256;
    using UD60x18 for uint256;

    uint256 private constant WAD = 1e18;

    // All the data used to calculate the key of the position
    struct Key {
        // The Agent that owns the exposure change of the Position
        address owner;
        // The Agent that can control modifications to the Position
        address operator;
        // The lower tick normalized price of the range order
        uint256 lower;
        // The upper tick normalized price of the range order
        uint256 upper;
        OrderType orderType;
        // ---- Values under are not used to compute the key hash but are included in this struct to reduce stack depth
        bool isCall;
        uint256 strike;
    }

    // All the data required to be saved in storage
    struct Data {
        // Used to track claimable fees over time
        uint256 lastFeeRate;
        // The amount of fees a user can claim now. Resets after claim
        uint256 claimableFees;
    }

    enum OrderType {
        CSUP, // Collateral <-> Short - Use Premiums
        CS, // Collateral <-> Short
        LC // Long <-> Collateral
    }

    struct Delta {
        int256 collateral;
        int256 longs;
        int256 shorts;
    }

    function keyHash(Key memory self) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    self.owner,
                    self.operator,
                    self.lower,
                    self.upper,
                    self.orderType
                )
            );
    }

    function isShort(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.CS || orderType == OrderType.CSUP;
    }

    function isLong(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.LC;
    }

    function pieceWiseLinear(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        // ToDo : Move check somewhere else ?
        if (self.lower >= self.upper)
            revert IPosition.Position__LowerGreaterOrEqualUpper();
        if (price <= self.lower) return 0;
        else if (self.lower < price && price < self.upper)
            return Pricing.proportion(self.lower, self.upper, price);
        else return WAD;
    }

    function pieceWiseQuadratic(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        // ToDo : Move check somewhere else ?
        if (self.lower >= self.upper)
            revert IPosition.Position__LowerGreaterOrEqualUpper();

        uint256 a;
        if (price <= self.lower) {
            return 0;
        } else if (self.lower < price && price < self.upper) {
            a = price;
        } else {
            a = self.upper;
        }

        uint256 numerator = (a.mul(a) - self.lower.mul(self.lower));
        uint256 denominator = 2 * (self.upper - self.lower);

        return numerator.div(denominator);
    }

    function collateralToContracts(
        uint256 _collateral,
        uint256 strike,
        bool isCall
    ) internal pure returns (uint256) {
        return isCall ? _collateral : _collateral.div(strike);
    }

    function contractsToCollateral(
        uint256 _contracts,
        uint256 strike,
        bool isCall
    ) internal pure returns (uint256) {
        return isCall ? _contracts : _contracts.mul(strike);
    }

    /// @notice Returns the per-tick liquidity phi (delta) for a specific position.
    function liquidityPerTick(
        Key memory self,
        uint256 size
    ) internal pure returns (uint256) {
        uint256 amountOfTicks = Pricing.amountOfTicksBetween(
            self.lower,
            self.upper
        );

        return size / amountOfTicks;
    }

    /// @notice Bid collateral either used to buy back options or revenue /
    ///         income generated from underwriting / selling options.
    ///         For a <= p <= b we have:
    ///
    ///         bid(p; a, b) = [ (p - a) / (b - a) ] * [ (a + p)  / 2 ]
    ///                      = (p^2 - a^2) / [2 * (b - a)]
    function bid(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        return
            contractsToCollateral(
                pieceWiseQuadratic(self, price).mul(size),
                self.strike,
                self.isCall
            );
    }

    /// @notice Total collateral held by the position. Note that here we do not
    ///         distinguish between ask- and bid-side collateral. This increases the
    ///         capital efficiency of the range order.
    function collateral(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256 _collateral) {
        uint256 nu = pieceWiseLinear(self, price);

        if (self.orderType.isShort()) {
            _collateral = contractsToCollateral(
                (WAD - nu).mul(size),
                self.strike,
                self.isCall
            );

            if (self.orderType == OrderType.CSUP) {
                _collateral -= (self.bid(size, self.upper) -
                    self.bid(size, price));
            } else {
                _collateral += self.bid(size, price);
            }
        } else if (self.orderType.isLong()) {
            _collateral = self.bid(size, price);
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    function contracts(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = pieceWiseLinear(self, price);

        if (self.orderType.isLong()) {
            return (WAD - nu).mul(size);
        }

        return nu.mul(size);
    }

    /// @notice Number of long contracts held in position at current price
    function long(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        if (self.orderType.isShort()) {
            return 0;
        } else if (self.orderType.isLong()) {
            return self.contracts(size, price);
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Number of short contracts held in position at current price
    function short(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        if (self.orderType.isShort()) {
            return self.contracts(size, price);
        } else if (self.orderType.isLong()) {
            return 0;
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Calculate the update for the Position. Either increments them in case
    ///         withdraw is False (i.e. in case there is a deposit) and otherwise
    ///         decreases them. Returns the change in collateral, longs, shorts.
    ///         These are transferred to (withdrawal) or transferred from (deposit)
    ///         the Agent (Position.operator).
    /// @param currentBalance The current balance of tokens
    /// @param amount The number of tokens deposited or withdrawn
    /// @param price The current market price, used to compute the change in
    ///              collateral, long and shorts due to the change in tokens
    /// @return delta Absolute change in collateral / longs / shorts due to change in tokens
    function calculatePositionUpdate(
        Key memory self,
        uint256 currentBalance,
        int256 amount,
        uint256 price
    ) internal pure returns (Delta memory delta) {
        if (currentBalance.toInt256() + amount < 0)
            revert IPosition.Position__InvalidPositionUpdate();

        uint256 absChangeTokens = Math.abs(amount);
        int256 sign = amount > 0 ? int256(1) : int256(-1);

        delta.collateral =
            sign *
            (self.collateral(absChangeTokens, price)).toInt256();

        delta.longs = sign * (self.long(absChangeTokens, price)).toInt256();
        delta.shorts = sign * (self.short(absChangeTokens, price)).toInt256();
    }
}

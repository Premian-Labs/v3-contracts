// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Math} from "@solidstate/contracts/utils/Math.sol";

import {UD60x18} from "@prb/math/UD60x18.sol";
import {SD59x18} from "@prb/math/SD59x18.sol";

import {iZERO, ZERO, ONE, TWO} from "./Constants.sol";
import {IPosition} from "./IPosition.sol";
import {SD} from "./PRBMathExtra.sol";
import {Pricing} from "./Pricing.sol";

/// @notice Keeps track of LP positions
///         Stores the lower and upper Ticks of a user's range order, and tracks the pro-rata exposure of the order.
library Position {
    using Math for int256;
    using Position for Position.Key;
    using Position for Position.KeyInternal;
    using Position for Position.OrderType;

    struct Key {
        // The Agent that owns the exposure change of the Position
        address owner;
        // The Agent that can control modifications to the Position
        address operator;
        // The lower tick normalized price of the range order (18 decimals)
        UD60x18 lower;
        // The upper tick normalized price of the range order (18 decimals)
        UD60x18 upper;
        OrderType orderType;
    }

    // All the data used to calculate the key of the position
    struct KeyInternal {
        // The Agent that owns the exposure change of the Position
        address owner;
        // The Agent that can control modifications to the Position
        address operator;
        // The lower tick normalized price of the range order (18 decimals)
        UD60x18 lower;
        // The upper tick normalized price of the range order (18 decimals)
        UD60x18 upper;
        OrderType orderType;
        // ---- Values under are not used to compute the key hash but are included in this struct to reduce stack depth
        bool isCall;
        // The option strike (18 decimals)
        UD60x18 strike;
    }

    // All the data required to be saved in storage
    struct Data {
        // Used to track claimable fees over time (18 decimals)
        UD60x18 lastFeeRate;
        // The amount of fees a user can claim now. Resets after claim (18 decimals)
        UD60x18 claimableFees;
        // The timestamp of the last deposit. Used to enforce withdrawal delay
        uint256 lastDeposit;
    }

    enum OrderType {
        CSUP, // Collateral <-> Short - Use Premiums
        CS, // Collateral <-> Short
        LC // Long <-> Collateral
    }

    struct Delta {
        SD59x18 collateral;
        SD59x18 longs;
        SD59x18 shorts;
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

    function keyHash(KeyInternal memory self) internal pure returns (bytes32) {
        return
            keyHash(
                Key({
                    owner: self.owner,
                    operator: self.operator,
                    lower: self.lower,
                    upper: self.upper,
                    orderType: self.orderType
                })
            );
    }

    function toKeyInternal(
        Key memory self,
        UD60x18 strike,
        bool isCall
    ) internal pure returns (KeyInternal memory) {
        return
            KeyInternal({
                owner: self.owner,
                operator: self.operator,
                lower: self.lower,
                upper: self.upper,
                orderType: self.orderType,
                strike: strike,
                isCall: isCall
            });
    }

    function isShort(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.CS || orderType == OrderType.CSUP;
    }

    function isLong(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.LC;
    }

    function pieceWiseLinear(
        KeyInternal memory self,
        UD60x18 price
    ) internal pure returns (UD60x18) {
        ensureLowerGreaterOrEqualUpper(self.lower, self.upper);

        if (price <= self.lower) return ZERO;
        else if (self.lower < price && price < self.upper)
            return Pricing.proportion(self.lower, self.upper, price);
        else return ONE;
    }

    function pieceWiseQuadratic(
        KeyInternal memory self,
        UD60x18 price
    ) internal pure returns (UD60x18) {
        ensureLowerGreaterOrEqualUpper(self.lower, self.upper);

        UD60x18 a;
        if (price <= self.lower) {
            return ZERO;
        } else if (self.lower < price && price < self.upper) {
            a = price;
        } else {
            a = self.upper;
        }

        UD60x18 numerator = (a * a - self.lower * self.lower);
        UD60x18 denominator = TWO * (self.upper - self.lower);

        return numerator / denominator;
    }

    function collateralToContracts(
        UD60x18 _collateral,
        UD60x18 strike,
        bool isCall
    ) internal pure returns (UD60x18) {
        return isCall ? _collateral : _collateral / strike;
    }

    /// @notice Converts the amount of contracts to the amount of collateral normalized to 18 decimals.
    ///         WARNING : Decimals needs to be scaled before using this amount for collateral transfers
    function contractsToCollateral(
        UD60x18 _contracts,
        UD60x18 strike,
        bool isCall
    ) internal pure returns (UD60x18) {
        return isCall ? _contracts : _contracts * strike;
    }

    /// @notice Returns the per-tick liquidity phi (delta) for a specific position.
    function liquidityPerTick(
        KeyInternal memory self,
        UD60x18 size
    ) internal pure returns (UD60x18) {
        UD60x18 amountOfTicks = Pricing.amountOfTicksBetween(
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
        KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) internal pure returns (UD60x18) {
        return
            contractsToCollateral(
                pieceWiseQuadratic(self, price) * size,
                self.strike,
                self.isCall
            );
    }

    /// @notice Total collateral held by the position. Note that here we do not
    ///         distinguish between ask- and bid-side collateral. This increases the
    ///         capital efficiency of the range order.
    function collateral(
        KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) internal pure returns (UD60x18 _collateral) {
        UD60x18 nu = pieceWiseLinear(self, price);

        if (self.orderType.isShort()) {
            _collateral = contractsToCollateral(
                (ONE - nu) * size,
                self.strike,
                self.isCall
            );

            if (self.orderType == OrderType.CSUP) {
                _collateral =
                    _collateral -
                    (self.bid(size, self.upper) - self.bid(size, price));
            } else {
                _collateral = _collateral + self.bid(size, price);
            }
        } else if (self.orderType.isLong()) {
            _collateral = self.bid(size, price);
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    function contracts(
        KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) internal pure returns (UD60x18) {
        UD60x18 nu = pieceWiseLinear(self, price);

        if (self.orderType.isLong()) {
            return (ONE - nu) * size;
        }

        return nu * size;
    }

    /// @notice Number of long contracts held in position at current price
    function long(
        KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) internal pure returns (UD60x18) {
        if (self.orderType.isShort()) {
            return ZERO;
        } else if (self.orderType.isLong()) {
            return self.contracts(size, price);
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Number of short contracts held in position at current price
    function short(
        KeyInternal memory self,
        UD60x18 size,
        UD60x18 price
    ) internal pure returns (UD60x18) {
        if (self.orderType.isShort()) {
            return self.contracts(size, price);
        } else if (self.orderType.isLong()) {
            return ZERO;
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Calculate the update for the Position. Either increments them in case
    ///         withdraw is False (i.e. in case there is a deposit) and otherwise
    ///         decreases them. Returns the change in collateral, longs, shorts.
    ///         These are transferred to (withdrawal) or transferred from (deposit)
    ///         the Agent (Position.operator).
    /// @param currentBalance The current balance of tokens (18 decimals)
    /// @param amount The number of tokens deposited or withdrawn (18 decimals)
    /// @param price The current market price, used to compute the change in
    ///              collateral, long and shorts due to the change in tokens (18 decimals)
    /// @return delta Absolute change in collateral / longs / shorts due to change in tokens
    function calculatePositionUpdate(
        KeyInternal memory self,
        UD60x18 currentBalance,
        SD59x18 amount,
        UD60x18 price
    ) internal pure returns (Delta memory delta) {
        if (currentBalance.intoSD59x18() + amount < iZERO)
            revert IPosition.Position__InvalidPositionUpdate(
                currentBalance,
                amount
            );

        UD60x18 absChangeTokens = amount.abs().intoUD60x18();
        SD59x18 sign = amount > iZERO ? SD(1e18) : SD(-1e18);

        delta.collateral =
            sign *
            (self.collateral(absChangeTokens, price)).intoSD59x18();

        delta.longs = sign * (self.long(absChangeTokens, price)).intoSD59x18();
        delta.shorts =
            sign *
            (self.short(absChangeTokens, price)).intoSD59x18();
    }

    function ensureLowerGreaterOrEqualUpper(
        UD60x18 lower,
        UD60x18 upper
    ) internal pure {
        if (lower >= upper)
            revert IPosition.Position__LowerGreaterOrEqualUpper(lower, upper);
    }
}

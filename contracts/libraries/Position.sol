// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

import {Math} from "@solidstate/contracts/utils/Math.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {iZERO, ZERO, ONE, TWO, UD50_ZERO, UD50_ONE, UD50_TWO} from "./Constants.sol";
import {IPosition} from "./IPosition.sol";
import {Pricing} from "./Pricing.sol";
import {UD50x28} from "./UD50x28.sol";
import {SD49x28} from "./SD49x28.sol";
import {PRBMathExtra} from "./PRBMathExtra.sol";

/// @notice Keeps track of LP positions.
///         Stores the lower and upper Ticks of a user's range order, and tracks the pro-rata exposure of the order.
library Position {
    using Math for int256;
    using Position for Position.Key;
    using Position for Position.KeyInternal;
    using Position for Position.OrderType;
    using PRBMathExtra for UD60x18;

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

    /// @notice All the data used to calculate the key of the position
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

    /// @notice The order type of a position
    enum OrderType {
        CSUP, // Collateral <-> Short - Use Premiums
        CS, // Collateral <-> Short
        LC // Long <-> Collateral
    }

    /// @notice All the data required to be saved in storage
    struct Data {
        // Used to track claimable fees over time (28 decimals)
        SD49x28 lastFeeRate;
        // The amount of fees a user can claim now. Resets after claim (18 decimals)
        UD60x18 claimableFees;
        // The timestamp of the last deposit. Used to enforce withdrawal delay
        uint256 lastDeposit;
    }

    struct Delta {
        SD59x18 collateral;
        SD59x18 longs;
        SD59x18 shorts;
    }

    /// @notice Returns the position key hash for `self`
    function keyHash(Key memory self) internal pure returns (bytes32) {
        return keccak256(abi.encode(self.owner, self.operator, self.lower, self.upper, self.orderType));
    }

    /// @notice Returns the position key hash for `self`
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

    /// @notice Returns the internal position key for `self`
    /// @param strike The strike of the option (18 decimals)
    function toKeyInternal(Key memory self, UD60x18 strike, bool isCall) internal pure returns (KeyInternal memory) {
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

    /// @notice Returns true if the position `orderType` is short
    function isShort(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.CS || orderType == OrderType.CSUP;
    }

    /// @notice Returns true if the position `orderType` is long
    function isLong(OrderType orderType) internal pure returns (bool) {
        return orderType == OrderType.LC;
    }

    /// @notice Returns the percentage by which the market price has passed through the lower and upper prices
    ///         from left to right.
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ///         Usage:
    ///         CS order: f(x) defines the amount of shorts of a CS order holding one unit of liquidity.
    ///         LC order: (1 - f(x)) defines the amount of longs of a LC order holding one unit of liquidity.
    ///
    ///         Function definition:
    ///         case 1. f(x) = 0                                for x < lower
    ///         case 2. f(x) = (x - lower) / (upper - lower)    for lower <= x <= upper
    ///         case 3. f(x) = 1                                for x > upper
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    function pieceWiseLinear(KeyInternal memory self, UD50x28 price) internal pure returns (UD50x28) {
        revertIfLowerGreaterOrEqualUpper(self.lower, self.upper);

        if (price <= self.lower.intoUD50x28()) return UD50_ZERO;
        else if (self.lower.intoUD50x28() < price && price < self.upper.intoUD50x28())
            return Pricing.proportion(self.lower, self.upper, price);
        else return UD50_ONE;
    }

    /// @notice Returns the amount of 'bid-side' collateral associated to a range order with one unit of liquidity.
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ///         Usage:
    ///         CS order: bid-side collateral defines the premiums generated from selling options.
    ///         LC order: bid-side collateral defines the collateral used to pay for buying long options.
    ///
    ///         Function definition:
    ///         case 1. f(x) = 0                                            for x < lower
    ///         case 2. f(x) = (price**2 - lower) / [2 * (upper - lower)]   for lower <= x <= upper
    ///         case 3. f(x) = (upper + lower) / 2                          for x > upper
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    function pieceWiseQuadratic(KeyInternal memory self, UD50x28 price) internal pure returns (UD50x28) {
        revertIfLowerGreaterOrEqualUpper(self.lower, self.upper);

        UD50x28 lowerUD50 = self.lower.intoUD50x28();
        UD50x28 upperUD50 = self.upper.intoUD50x28();

        UD50x28 a;
        if (price <= lowerUD50) {
            return UD50_ZERO;
        } else if (lowerUD50 < price && price < upperUD50) {
            a = price;
        } else {
            a = upperUD50;
        }

        UD50x28 numerator = (a * a - lowerUD50 * lowerUD50);
        UD50x28 denominator = UD50_TWO * (upperUD50 - lowerUD50);

        return (numerator / denominator);
    }

    /// @notice Converts `_collateral` to the amount of contracts normalized to 18 decimals
    /// @param strike The strike price (18 decimals)
    function collateralToContracts(UD60x18 _collateral, UD60x18 strike, bool isCall) internal pure returns (UD60x18) {
        return isCall ? _collateral : _collateral / strike;
    }

    /// @notice Converts `_contracts` to the amount of collateral normalized to 18 decimals
    /// @dev WARNING: Decimals needs to be scaled before using this amount for collateral transfers
    /// @param strike The strike price (18 decimals)
    function contractsToCollateral(UD60x18 _contracts, UD60x18 strike, bool isCall) internal pure returns (UD60x18) {
        return isCall ? _contracts : _contracts * strike;
    }

    /// @notice Converts `_collateral` to the amount of contracts normalized to 28 decimals
    /// @param strike The strike price (18 decimals)
    function collateralToContracts(UD50x28 _collateral, UD60x18 strike, bool isCall) internal pure returns (UD50x28) {
        return isCall ? _collateral : _collateral / strike.intoUD50x28();
    }

    /// @notice Converts `_contracts` to the amount of collateral normalized to 28 decimals
    /// @dev WARNING: Decimals needs to be scaled before using this amount for collateral transfers
    /// @param strike The strike price (18 decimals)
    function contractsToCollateral(UD50x28 _contracts, UD60x18 strike, bool isCall) internal pure returns (UD50x28) {
        return isCall ? _contracts : _contracts * strike.intoUD50x28();
    }

    /// @notice Returns the per-tick liquidity phi (delta) for a specific position key `self`
    /// @param size The contract amount (18 decimals)
    function liquidityPerTick(KeyInternal memory self, UD60x18 size) internal pure returns (UD50x28) {
        UD60x18 amountOfTicks = Pricing.amountOfTicksBetween(self.lower, self.upper);

        return size.intoUD50x28() / amountOfTicks.intoUD50x28();
    }

    /// @notice Returns the bid collateral (18 decimals) either used to buy back options or revenue/ income generated
    ///         from underwriting / selling options.
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    ///         For a <= p <= b we have:
    ///
    ///         bid(p; a, b) = [ (p - a) / (b - a) ] * [ (a + p)  / 2 ]
    ///                      = (p^2 - a^2) / [2 * (b - a)]
    ///         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// @param self The internal position key
    /// @param size The contract amount (18 decimals)
    /// @param price The current market price (28 decimals)
    function bid(KeyInternal memory self, UD60x18 size, UD50x28 price) internal pure returns (UD60x18) {
        return
            contractsToCollateral(pieceWiseQuadratic(self, price) * size.intoUD50x28(), self.strike, self.isCall)
                .intoUD60x18();
    }

    /// @notice Returns the total collateral (18 decimals) held by the position key `self`. Note that here we do not
    ///         distinguish between ask- and bid-side collateral. This increases the capital efficiency of the range order
    /// @param size The contract amount (18 decimals)
    /// @param price The current market price (28 decimals)
    function collateral(
        KeyInternal memory self,
        UD60x18 size,
        UD50x28 price
    ) internal pure returns (UD60x18 _collateral) {
        UD50x28 nu = pieceWiseLinear(self, price);

        if (self.orderType.isShort()) {
            _collateral = contractsToCollateral((UD50_ONE - nu) * size.intoUD50x28(), self.strike, self.isCall)
                .intoUD60x18();

            if (self.orderType == OrderType.CSUP) {
                _collateral = _collateral - (self.bid(size, self.upper.intoUD50x28()) - self.bid(size, price));
            } else {
                _collateral = _collateral + self.bid(size, price);
            }
        } else if (self.orderType.isLong()) {
            _collateral = self.bid(size, price);
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Returns the total contracts (18 decimals) held by the position key `self`
    /// @param size The contract amount (18 decimals)
    /// @param price The current market price (28 decimals)
    function contracts(KeyInternal memory self, UD60x18 size, UD50x28 price) internal pure returns (UD60x18) {
        UD50x28 nu = pieceWiseLinear(self, price);

        if (self.orderType.isLong()) {
            return ((UD50_ONE - nu) * size.intoUD50x28()).intoUD60x18();
        }

        return (nu * size.intoUD50x28()).intoUD60x18();
    }

    /// @notice Returns the number of long contracts (18 decimals) held in position `self` at current price
    /// @param size The contract amount (18 decimals)
    /// @param price The current market price (28 decimals)
    function long(KeyInternal memory self, UD60x18 size, UD50x28 price) internal pure returns (UD60x18) {
        if (self.orderType.isShort()) {
            return ZERO;
        } else if (self.orderType.isLong()) {
            return self.contracts(size, price);
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Returns the number of short contracts (18 decimals) held in position `self` at current price
    /// @param size The contract amount (18 decimals)
    /// @param price The current market price (28 decimals)
    function short(KeyInternal memory self, UD60x18 size, UD50x28 price) internal pure returns (UD60x18) {
        if (self.orderType.isShort()) {
            return self.contracts(size, price);
        } else if (self.orderType.isLong()) {
            return ZERO;
        } else {
            revert IPosition.Position__InvalidOrderType();
        }
    }

    /// @notice Calculate the update for the Position. Either increments them in case withdraw is False (i.e. in case
    ///         there is a deposit) and otherwise decreases them. Returns the change in collateral, longs, shorts. These
    ///         are transferred to (withdrawal)or transferred from (deposit) the Agent (Position.operator).
    /// @param currentBalance The current balance of tokens (18 decimals)
    /// @param amount The number of tokens deposited or withdrawn (18 decimals)
    /// @param price The current market price, used to compute the change in collateral, long and shorts due to the
    ///        change in tokens (28 decimals)
    /// @return delta Absolute change in collateral / longs / shorts due to change in tokens
    function calculatePositionUpdate(
        KeyInternal memory self,
        UD60x18 currentBalance,
        SD59x18 amount,
        UD50x28 price
    ) internal pure returns (Delta memory delta) {
        if (currentBalance.intoSD59x18() + amount < iZERO)
            revert IPosition.Position__InvalidPositionUpdate(currentBalance, amount);

        UD60x18 absChangeTokens = amount.abs().intoUD60x18();
        SD59x18 sign = amount > iZERO ? sd(1e18) : sd(-1e18);

        delta.collateral = sign * (self.collateral(absChangeTokens, price)).intoSD59x18();

        delta.longs = sign * (self.long(absChangeTokens, price)).intoSD59x18();
        delta.shorts = sign * (self.short(absChangeTokens, price)).intoSD59x18();
    }

    /// @notice Revert if `lower` is greater or equal to `upper`
    function revertIfLowerGreaterOrEqualUpper(UD60x18 lower, UD60x18 upper) internal pure {
        if (lower >= upper) revert IPosition.Position__LowerGreaterOrEqualUpper(lower, upper);
    }
}

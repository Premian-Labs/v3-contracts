// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {Math} from "@solidstate/contracts/utils/Math.sol";

import {Pricing} from "./Pricing.sol";
import {WadMath} from "./WadMath.sol";

/// @notice Keeps track of LP positions
///         Stores the lower and upper Ticks of a user's range order, and tracks the pro-rata exposure of the order.
library Position {
    using Math for int256;
    using WadMath for uint256;
    using Position for Position.Key;

    error Position__InsufficientBidLiquidity();
    error Position__InsufficientFunds();
    error Position__NotEnoughCollateral();

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
        uint256 strike;
        bool isCall;
    }

    // All the data required to be saved in storage
    struct Data {
        // The amount of ask (bid) collateral the LP provides
        uint256 collateral; // ToDo : Remove
        // The amount of long (short) contracts the LP provides
        uint256 contracts; // ToDo : Remove
        uint256 initialAmount;
        // Used to track claimable fees over time
        uint256 lastFeeRate;
        // The amount of fees a user can claim now. Resets after claim
        uint256 claimableFees;
        // Whether side is BUY or SELL
        bool isBuy; // ToDo : Remove
    }

    enum OrderType {
        BUY_WITH_COLLATERAL,
        BUY_WITH_SHORTS,
        SELL_WITH_COLLATERAL,
        SELL_WITH_LONGS
    }

    struct Liquidity {
        uint256 collateral;
        uint256 long;
        uint256 short;
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

    function opposite(OrderType orderType) internal pure returns (OrderType) {
        if (orderType == OrderType.BUY_WITH_COLLATERAL)
            return OrderType.SELL_WITH_LONGS;
        else if (orderType == OrderType.SELL_WITH_LONGS)
            return OrderType.BUY_WITH_COLLATERAL;
        else if (orderType == OrderType.BUY_WITH_SHORTS)
            return OrderType.SELL_WITH_COLLATERAL;
        else if (orderType == OrderType.SELL_WITH_COLLATERAL)
            return OrderType.BUY_WITH_SHORTS;
        else revert();
    }

    function isLeft(OrderType orderType) internal pure returns (bool) {
        return
            orderType == OrderType.BUY_WITH_SHORTS ||
            orderType == OrderType.BUY_WITH_COLLATERAL;
    }

    function isRight(OrderType orderType) internal pure returns (bool) {
        return
            orderType == OrderType.SELL_WITH_COLLATERAL ||
            orderType == OrderType.SELL_WITH_LONGS;
    }

    function proportion(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        if (price < self.lower) return 0;
        else if (self.lower <= price && price < self.upper)
            return Pricing.proportion(self.lower, self.upper, price);
        return 1e18;
    }

    function pieceWiseLinear(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        if (price < self.lower) return 0;
        else if (self.lower <= price && price < self.upper)
            return self.proportion(price);
        else return 1e18;
    }

    function collateralToContracts(
        uint256 _collateral,
        uint256 strike,
        bool isCall
    ) internal pure returns (uint256) {
        return isCall ? _collateral : _collateral.divWad(strike);
    }

    function contractsToCollateral(
        uint256 _contracts,
        uint256 strike,
        bool isCall
    ) internal pure returns (uint256) {
        return isCall ? _contracts : _contracts.mulWad(strike);
    }

    function averagePrice(Key memory self) internal pure returns (uint256) {
        return Math.average(self.lower, self.upper);
    }

    function liquidity(
        Key memory self,
        Data memory data
    ) internal pure returns (uint256 contractsLiquidity) {
        if (self.orderType == OrderType.SELL_WITH_COLLATERAL) {
            return data.initialAmount.divWad(1e18 - self.averagePrice());
        } else if (self.orderType == OrderType.BUY_WITH_COLLATERAL) {
            return data.initialAmount.divWad(self.averagePrice());
        } else if (
            self.orderType == OrderType.SELL_WITH_LONGS ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            return data.initialAmount;
        }

        revert();
    }

    /// @notice Returns the per-tick liquidity phi (delta) for a specific position.
    function liquidityPerTick(
        Key memory self,
        Data memory data
    ) internal pure returns (uint256) {
        uint256 amountOfTicks = Pricing.amountOfTicksBetween(
            self.lower,
            self.upper
        );

        return self.liquidity(data) / amountOfTicks;
    }

    function transitionPrice(
        Key memory self,
        Data memory data
    ) internal pure returns (uint256) {
        uint256 _liquidity = self.liquidity(data);
        uint256 shift = _liquidity == 0
            ? 0
            : data.contracts.divWad(_liquidity).mulWad(self.upper - self.lower);

        return data.isBuy ? self.upper - shift : self.lower + shift;
    }

    /// @notice Represents the total amount of bid liquidity the position is holding
    /// at a particular price. In other words, it is the total amount of buying
    /// power the position has at the current price.
    function bidLiquidity(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        return self.pieceWiseLinear(price).mulWad(self.liquidity(data));
    }

    /// @notice Represents the total amount of ask liquidity the position is holding
    /// at a particular price. In other words, it is the total amount of
    /// selling power the position has at the current price.
    /// Can also be computed as,
    ///     total_bid(p) = ask(p) + long(p)
    function askLiquidity(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        return
            (1e18 - self.pieceWiseLinear(price)).mulWad(self.liquidity(data));
    }

    /// @notice Bid collateral either used to buy back options or revenue /
    ///         income generated from underwriting / selling options.
    function bid(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.pieceWiseLinear(price);

        // overworked to avoid numerical rounding errors
        uint256 quotePrice;
        if (price < self.lower) {
            quotePrice = self.lower;
        } else if (self.lower <= price && price < self.upper) {
            quotePrice = Math.average(price, self.lower);
        } else {
            quotePrice = self.averagePrice();
        }

        uint256 result = nu.mulWad(self.liquidity(data)).mulWad(quotePrice);

        return contractsToCollateral(result, self.strike, self.isCall);
    }

    // ToDo : Remove
    /// @notice
    ///    nu = proportion(p, p^*, p_upper)
    ///    Right-side:
    ///        Amount of ask-side collateral available when underwriting.
    ///        ask(p) = (1 - nu) *  c
    ///    Left-side:
    ///        Amount of ask-side collateral liberated through closing short
    ///        positions.
    ///        ask(p) = (1- nu) * d
    function ask(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);
        uint256 x = data.isBuy
            ? contractsToCollateral(data.contracts, self.strike, self.isCall)
            : data.collateral;
        return (1e18 - nu).mulWad(x);
    }

    /// @notice Total collateral held by the position. Note that here we do not
    ///         distinguish between ask- and bid-side collateral. This increases the
    ///         capital efficiency of the range order.
    function collateral(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256 _collateral) {
        uint256 nu = pieceWiseLinear(self, price);

        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            _collateral = (1e18 - nu).mulWad(self.liquidity(data));
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            _collateral = self.bid(data, price);
        } else {
            revert();
        }
    }

    function contracts(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = pieceWiseLinear(self, price);

        if (
            self.orderType == OrderType.SELL_WITH_LONGS ||
            self.orderType == OrderType.BUY_WITH_COLLATERAL
        ) {
            return (1e18 - nu).mulWad(self.liquidity(data));
        }

        return nu.mulWad(self.liquidity(data));
    }

    /// @notice Number of long contracts held in position at current price
    function long(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            return 0;
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            return self.contracts(data, price);
        } else {
            revert();
        }
    }

    /// @notice Number of short contracts held in position at current price
    function short(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            return self.contracts(data, price);
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            return 0;
        } else {
            revert();
        }
    }

    function assertSufficientBidLiquidity(
        Key memory self,
        Data memory data,
        uint256 _collateral,
        uint256 _contracts,
        bool withdrawal
    ) internal pure {
        _collateral = withdrawal
            ? data.collateral - _collateral
            : data.collateral + _collateral;
        _contracts = withdrawal
            ? data.contracts - _contracts
            : data.contracts + _contracts;

        if (
            _collateral <
            contractsToCollateral(self.averagePrice(), self.strike, self.isCall)
                .mulWad(_contracts)
        ) revert Position__InsufficientBidLiquidity();
    }

    function assertSufficientFunds(
        Data memory data,
        uint256 _collateral,
        uint256 _contracts
    ) internal pure {
        if (_collateral > data.collateral || _contracts > data.contracts)
            revert Position__InsufficientFunds();
    }

    // ToDo : Update
    /// @notice Convert position to opposite side to make it modifiable. A position is
    ///    modifiable if it's side does not need updating.
    function flipSide(
        Key memory self,
        Data storage data,
        uint256 price
    ) internal {
        bool isOrderLeft = self.upper <= price;

        if (isOrderLeft != data.isBuy) return;

        if (data.isBuy) {
            data.collateral = contractsToCollateral(
                data.contracts,
                self.strike,
                self.isCall
            );
            data.contracts = self.liquidity(data) - data.contracts;
        } else {
            data.collateral = self.liquidity(data).mulWad(
                contractsToCollateral(
                    self.averagePrice(),
                    self.strike,
                    self.isCall
                )
            );
            data.contracts = Position.collateralToContracts(
                data.collateral,
                self.strike,
                self.isCall
            );
        }

        data.isBuy = !data.isBuy;
    }
}

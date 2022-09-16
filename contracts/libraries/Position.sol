// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {Exposure} from "./Exposure.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

/**
 * @notice Keeps track of LP positions
           Stores the lower and upper Ticks of a user's range order, and tracks
           the pro-rata exposure of the order.

           P_DL:= The price at which all long options are closed
           P_DS:= The price at which all short options are covered

           C_B => DL:= C_B / P_bar(P_DL, T_lower)         (1 unit of bid collateral = (1 / P_bar) contracts of long options)
           C_A => DS:= C_A                                (1 unit of ask collateral = 1 contract of short options)
           DL => C_B:= DL * P_bar(T_lower, P_DL)          (1 unit of long options = P_bar units of bid collateral)
           DS => C_A:= DS * (1 - P_bar(T_upper, P_DS))    (1 contract of short options = (1 - P_bar) unit of ask collateral)
 */
library Position {
    using Position for Position.Data;

    struct Data {
        // The Agent that owns the exposure change of the Position.
        address owner;
        // The Agent that can control modifications to the Position.
        address operator;
        // The direction of the range order.
        PoolStorage.TradeSide side;
        // ToDo : Probably can use uint64
        // The lower tick price of the range order.
        uint256 lower;
        // The upper tick price of the range order.
        uint256 upper;
        // The amount of bid collateral the LP provides.
        uint256 bid;
        // The amount of bid collateral the LP provides.
        uint256 ask;
        // The amount of long contracts the LP provides.
        uint256 long;
        // The amount of short contracts the LP provides.
        uint256 short;
        Exposure.Data lastExposure;
    }

    function transitionPrice(Data memory self) internal pure returns (uint256) {
        return self._transitionPrice(true);
    }

    function _transitionPrice(Data memory self, bool useBidAveragePrice)
        internal
        pure
        returns (uint256)
    {
        if (self.side == PoolStorage.TradeSide.BUY) {
            uint256 minBid;
            if (useBidAveragePrice) {
                minBid = (self.bidAveragePrice() * self.short) / 1e18;
            } else {
                minBid = (self.averagePrice() * self.short) / 1e18;
            }

            uint256 _lambdaBid = self.bid + minBid;

            return
                self.upper -
                ((minBid / _lambdaBid) * (self.upper - self.lower)) /
                1e18;
        }

        return
            self.long +
            ((self.long / self.lambdaAsk()) * (self.upper - self.lower)) /
            1e18;
    }

    function averagePrice(Data memory self) internal pure returns (uint256) {
        return (self.upper + self.lower) / 2;
    }

    function bidAveragePrice(Data memory self) internal pure returns (uint256) {
        return (self._transitionPrice(false) + self.lower) / 2;
    }

    /**
     * @notice The total number of long contracts that must be bought to move through this Position's range.
     */
    function lambdaBid(Data memory self) internal pure returns (uint256) {
        return
            self.bid == 0
                ? self.short
                : self.short + (self.bid * 1e18) / self.bidAveragePrice();
    }

    /**
     * @notice The total number of short contracts that must be sold to move through this Position's range.
     */
    function lambdaAsk(Data memory self) internal pure returns (uint256) {
        return self.ask + self.long;
    }

    function _lambda(Data memory self) internal pure returns (uint256) {
        return self.lambdaBid() + self.lambdaAsk();
    }

    /**
     * @notice The per-tick liquidity delta for a specific position.
     */
    function delta(Data memory self, uint256 minTickDistance)
        internal
        pure
        returns (uint256)
    {
        return
            (((self._lambda() * (self.upper - self.lower)) / 1e18) *
                minTickDistance) / 1e18;
    }

    function add(Data memory self, Data memory other)
        internal
        pure
        returns (Data memory)
    {
        self.bid += other.bid;
        self.ask += other.ask;
        self.long += other.long;
        self.short += other.short;

        return self;
    }

    function sub(Data memory self, Data memory other)
        internal
        pure
        returns (Data memory)
    {
        self.bid -= other.bid;
        self.ask -= other.ask;
        self.long -= other.long;
        self.short -= other.short;

        return self;
    }

    // ToDo : See if we need this
    //    function neg(PositionData memory self)
    //        internal
    //        view
    //        returns (PositionData memory)
    //    {
    //        self.bid = -self.bid;
    //        self.ask = -self.ask;
    //        self.long = -self.long;
    //        self.short = -self.short;
    //
    //        return self;
    //    }
}

// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PoolStorage} from "../pool/PoolStorage.sol";

library Position {
    using Position for Position.PositionData;

    struct PositionData {
        address owner;
        address operator;
        PoolStorage.TradeSide side;
        // ToDo : Probably can use uint64
        uint256 lower;
        uint256 upper;
        uint256 bid;
        uint256 ask;
        uint256 long;
        uint256 short;
        PoolStorage.Exposure lastExposure;
    }

    function transitionPrice(PositionData memory self)
        internal
        pure
        returns (uint256)
    {
        return self._transitionPrice(true);
    }

    function _transitionPrice(PositionData memory self, bool useBidAveragePrice)
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

    function averagePrice(PositionData memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.upper + self.lower) / 2;
    }

    function bidAveragePrice(PositionData memory self)
        internal
        pure
        returns (uint256)
    {
        return (self._transitionPrice(false) + self.lower) / 2;
    }

    /**
     * @notice The total number of long contracts that must be bought to move through this Position's range.
     */
    function lambdaBid(PositionData memory self)
        internal
        pure
        returns (uint256)
    {
        return
            self.bid == 0
                ? self.short
                : self.short + (self.bid * 1e18) / self.bidAveragePrice();
    }

    /**
     * @notice The total number of short contracts that must be sold to move through this Position's range.
     */
    function lambdaAsk(PositionData memory self)
        internal
        pure
        returns (uint256)
    {
        return self.ask + self.long;
    }

    function _lambda(PositionData memory self) internal pure returns (uint256) {
        return self.lambdaBid() + self.lambdaAsk();
    }

    function delta(PositionData memory self, uint256 minTickDistance)
        internal
        pure
        returns (uint256)
    {
        return
            (((self._lambda() * (self.upper - self.lower)) / 1e18) *
                minTickDistance) / 1e18;
    }

    function add(PositionData memory self, PositionData memory other)
        internal
        pure
        returns (PositionData memory)
    {
        self.bid += other.bid;
        self.ask += other.ask;
        self.long += other.long;
        self.short += other.short;

        return self;
    }

    function sub(PositionData memory self, PositionData memory other)
        internal
        pure
        returns (PositionData memory)
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

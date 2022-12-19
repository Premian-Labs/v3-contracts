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

    uint256 private constant WAD = 1e18;

    error Position__InsufficientBidLiquidity();
    error Position__InsufficientFunds();
    error Position__NotEnoughCollateral();
    error Position__WrongOrderType();
    error Position__WrongContractsToCollateralRatio();

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
        uint256 size;
        // Used to track claimable fees over time
        uint256 lastFeeRate;
        // The amount of fees a user can claim now. Resets after claim
        uint256 claimableFees;
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
        else revert Position__WrongOrderType();
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

    function isLeft(Key memory self) internal pure returns (bool) {
        return isLeft(self.orderType);
    }

    function isRight(Key memory self) internal pure returns (bool) {
        return isRight(self.orderType);
    }

    function proportion(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        if (price < self.lower) return 0;
        else if (self.lower <= price && price < self.upper)
            return Pricing.proportion(self.lower, self.upper, price);
        return WAD;
    }

    function pieceWiseLinear(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        if (price < self.lower) return 0;
        else if (self.lower <= price && price < self.upper)
            return self.proportion(price);
        else return WAD;
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
            return data.size.divWad(WAD - self.averagePrice());
        } else if (self.orderType == OrderType.BUY_WITH_COLLATERAL) {
            return data.size.divWad(self.averagePrice());
        } else if (
            self.orderType == OrderType.SELL_WITH_LONGS ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            return data.size;
        }

        revert Position__WrongOrderType();
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

    // ToDo : Remove ?
    //    /// @notice Represents the total amount of bid liquidity the position is holding
    //    /// at a particular price. In other words, it is the total amount of buying
    //    /// power the position has at the current price.
    //    function bidLiquidity(
    //        Key memory self,
    //        Data memory data,
    //        uint256 price
    //    ) internal pure returns (uint256) {
    //        return self.pieceWiseLinear(price).mulWad(self.liquidity(data));
    //    }
    //
    //    /// @notice Represents the total amount of ask liquidity the position is holding
    //    /// at a particular price. In other words, it is the total amount of
    //    /// selling power the position has at the current price.
    //    /// Can also be computed as,
    //    ///     total_bid(p) = ask(p) + long(p)
    //    function askLiquidity(
    //        Key memory self,
    //        Data memory data,
    //        uint256 price
    //    ) internal pure returns (uint256) {
    //        return (WAD - self.pieceWiseLinear(price)).mulWad(self.liquidity(data));
    //    }

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
            _collateral = (WAD - nu).mulWad(self.liquidity(data));
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            _collateral = self.bid(data, price);
        } else {
            revert Position__WrongOrderType();
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
            return (WAD - nu).mulWad(self.liquidity(data));
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
            revert Position__WrongOrderType();
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
            revert Position__WrongOrderType();
        }
    }

    // ToDo : Should we move this ?
    function assertSatisfiesRatio(
        Key memory self,
        Data memory data,
        uint256 price,
        uint256 _collateral,
        uint256 _contracts
    ) internal pure {
        uint256 pCollateral = self.collateral(data, price);
        uint256 pContracts = self.contracts(data, price);

        if (pCollateral == 0 && _collateral > 0)
            revert Position__WrongContractsToCollateralRatio();
        if (pContracts == 0 && _contracts > 0)
            revert Position__WrongContractsToCollateralRatio();

        uint256 depositRatio = _contracts.divWad(_collateral);
        uint256 positionRatio = pContracts.divWad(pCollateral);
        if (depositRatio != positionRatio)
            revert Position__WrongContractsToCollateralRatio();
    }

    function calculateAssetChange(
        Key memory self,
        Data memory data,
        uint256 price,
        uint256 _collateral,
        uint256 _longs,
        uint256 _shorts
    ) internal pure returns (uint256) {
        uint256 _contracts = Math.max(_longs, _shorts);
        self.assertSatisfiesRatio(data, price, _collateral, _contracts);

        uint256 nu = self.pieceWiseLinear(price);
        uint256 size;
        if (self.orderType == OrderType.SELL_WITH_COLLATERAL) {
            if (_longs > 0) revert(); // ToDo : Add custom error
            if (price > self.lower) {
                uint256 _liquidity = _shorts.divWad(nu);
                size = contractsToCollateral(
                    _liquidity.mulWad(WAD - self.averagePrice()),
                    self.strike,
                    self.isCall
                );
            } else {
                size = _collateral;
                if (_shorts > 0) revert(); // ToDo : Add custom error
            }
        } else if (self.orderType == OrderType.BUY_WITH_COLLATERAL) {
            if (_shorts > 0) revert(); // ToDo : Add custom error
            if (self.lower < price && price < self.upper) {
                uint256 _liquidity = _longs.divWad(WAD - nu);
                size = contractsToCollateral(
                    _liquidity.mulWad(self.averagePrice()),
                    self.strike,
                    self.isCall
                );
            } else if (price <= self.lower) {
                size = contractsToCollateral(
                    _longs.mulWad(self.averagePrice()),
                    self.strike,
                    self.isCall
                );
            } else {
                size = _collateral;
                if (_longs > 0) revert(); // ToDo : Add custom error
            }
        } else if (self.orderType == OrderType.SELL_WITH_LONGS) {
            if (_shorts > 0) revert(); // ToDo : Add custom error
            if (price < self.upper) {
                size = _longs.divWad(WAD - nu);
            } else {
                size = collateralToContracts(
                    _collateral.divWad(self.averagePrice()),
                    self.strike,
                    self.isCall
                );
                if (_longs > 0) revert(); // ToDo : Add custom error
            }
        } else if (self.orderType == OrderType.BUY_WITH_SHORTS) {
            if (_longs > 0) revert(); // ToDo : Add custom error
            if (price > self.lower) {
                size = _shorts.divWad(nu);
            } else {
                size = collateralToContracts(
                    _collateral.divWad(WAD - self.averagePrice()),
                    self.strike,
                    self.isCall
                );
                if (_shorts > 0) revert(); // ToDo : Add custom error
            }
        } else {
            revert Position__WrongOrderType();
        }

        return size;
    }
}

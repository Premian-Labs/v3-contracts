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

    error Position__InvalidAssetChange();
    error Position__InvalidContractsToCollateralRatio();
    error Position__InvalidOrderType();
    error Position__LowerGreaterOrEqualUpper();

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
        BUY_WITH_COLLATERAL, // Buy options using deposited collateral
        BUY_WITH_SHORTS, // Buy options using deposited shorts (Premiums are NOT used)
        BUY_WITH_SHORTS_USE_PREMIUMS, // Buy options using deposited shorts (Premiums are used)
        SELL_WITH_COLLATERAL, // Sell options using deposited collateral (Premiums are NOT used)
        SELL_WITH_COLLATERAL_USE_PREMIUMS, // Sell options using deposited collateral (Premiums are used)
        SELL_WITH_LONGS // Sell options using deposited longs
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
        else if (orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS)
            return OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS;
        else if (orderType == OrderType.SELL_WITH_COLLATERAL)
            return OrderType.BUY_WITH_SHORTS;
        else if (orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS)
            return OrderType.BUY_WITH_SHORTS_USE_PREMIUMS;
        else revert Position__InvalidOrderType();
    }

    function isLeft(OrderType orderType) internal pure returns (bool) {
        return
            orderType == OrderType.BUY_WITH_SHORTS ||
            orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS ||
            orderType == OrderType.BUY_WITH_COLLATERAL;
    }

    function isRight(OrderType orderType) internal pure returns (bool) {
        return
            orderType == OrderType.SELL_WITH_COLLATERAL ||
            orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS ||
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
        // ToDo : Move check somewhere else ?
        if (self.lower >= self.upper)
            revert Position__LowerGreaterOrEqualUpper();
        if (price < self.lower) return 0;
        else if (self.lower <= price && price < self.upper)
            return self.proportion(price);
        else return WAD;
    }

    function pieceWiseQuadratic(
        Key memory self,
        uint256 price
    ) internal pure returns (uint256) {
        // ToDo : Move check somewhere else ?
        if (self.lower >= self.upper)
            revert Position__LowerGreaterOrEqualUpper();

        uint256 a;
        if (price < self.lower) {
            a = self.lower;
        } else if (self.lower <= price && price < self.upper) {
            a = price;
        } else {
            a = self.upper;
        }

        uint256 numerator = (a.mulWad(a) - self.lower.mulWad(self.lower));
        uint256 denominator = (2 * WAD) * (self.upper - self.lower);

        return numerator.divWad(denominator);
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
        uint256 size
    ) internal pure returns (uint256 contractsLiquidity) {
        if (self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS) {
            return size.divWad(WAD - self.averagePrice());
        } else if (self.orderType == OrderType.BUY_WITH_COLLATERAL) {
            return size.divWad(self.averagePrice());
        } else if (
            self.orderType == OrderType.SELL_WITH_LONGS ||
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.BUY_WITH_SHORTS ||
            self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS
        ) {
            return size;
        }

        revert Position__InvalidOrderType();
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

        return self.liquidity(size) / amountOfTicks;
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
                pieceWiseQuadratic(self, price).mulWad(self.liquidity(size)),
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

        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS ||
            self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS ||
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            _collateral = contractsToCollateral(
                (WAD - nu).mulWad(self.liquidity(size)),
                self.strike,
                self.isCall
            );

            if (
                self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS ||
                self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS
            ) {
                _collateral -= (self.bid(size, self.upper) -
                    self.bid(size, price));
            } else {
                _collateral += self.bid(size, price);
            }
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            _collateral = self.bid(size, price);
        } else {
            revert Position__InvalidOrderType();
        }
    }

    function contracts(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = pieceWiseLinear(self, price);

        if (
            self.orderType == OrderType.SELL_WITH_LONGS ||
            self.orderType == OrderType.BUY_WITH_COLLATERAL
        ) {
            return (WAD - nu).mulWad(self.liquidity(size));
        }

        return nu.mulWad(self.liquidity(size));
    }

    /// @notice Number of long contracts held in position at current price
    function long(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS ||
            self.orderType == OrderType.BUY_WITH_SHORTS ||
            self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS
        ) {
            return 0;
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            return self.contracts(size, price);
        } else {
            revert Position__InvalidOrderType();
        }
    }

    /// @notice Number of short contracts held in position at current price
    function short(
        Key memory self,
        uint256 size,
        uint256 price
    ) internal pure returns (uint256) {
        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS ||
            self.orderType == OrderType.BUY_WITH_SHORTS ||
            self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS
        ) {
            return self.contracts(size, price);
        } else if (
            self.orderType == OrderType.BUY_WITH_COLLATERAL ||
            self.orderType == OrderType.SELL_WITH_LONGS
        ) {
            return 0;
        } else {
            revert Position__InvalidOrderType();
        }
    }

    // ToDo : Should we move this ?
    function assertSatisfiesRatio(
        Key memory self,
        uint256 currentSize,
        uint256 price,
        uint256 _collateral,
        uint256 _contracts
    ) internal pure {
        uint256 pCollateral = self.collateral(currentSize, price);
        uint256 pContracts = self.contracts(currentSize, price);

        if (pCollateral == 0 && _collateral > 0)
            revert Position__InvalidContractsToCollateralRatio();
        if (pContracts == 0 && _contracts > 0)
            revert Position__InvalidContractsToCollateralRatio();

        uint256 depositRatio = _contracts.divWad(_collateral);
        uint256 positionRatio = pContracts.divWad(pCollateral);
        if (depositRatio != positionRatio)
            revert Position__InvalidContractsToCollateralRatio();
    }

    function calculateAssetChangeSellWithCollateral(
        Key memory self,
        uint256 price,
        uint256 _collateral,
        uint256 _longs,
        uint256 _shorts,
        uint256 nu
    ) internal pure returns (uint256 size) {
        if (_longs > 0) revert Position__InvalidAssetChange();

        if (price > self.lower) {
            uint256 _liquidity = _shorts.divWad(nu);
            size = contractsToCollateral(
                self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS
                    ? _liquidity.mulWad(WAD - self.averagePrice())
                    : _liquidity,
                self.strike,
                self.isCall
            );
        } else {
            size = _collateral;

            if (_shorts > 0) revert Position__InvalidAssetChange();
        }
    }

    function calculateAssetChangeBuyWithCollateral(
        Key memory self,
        uint256 price,
        uint256 _collateral,
        uint256 _longs,
        uint256 _shorts,
        uint256 nu
    ) internal pure returns (uint256 size) {
        if (_shorts > 0) revert Position__InvalidAssetChange();

        if (self.lower < price && price < self.upper) {
            size = contractsToCollateral(
                _longs.divWad(WAD - nu).mulWad(self.averagePrice()),
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

            if (_longs > 0) revert Position__InvalidAssetChange();
        }
    }

    function calculateAssetChangeSellWithLongs(
        Key memory self,
        uint256 price,
        uint256 _collateral,
        uint256 _longs,
        uint256 _shorts,
        uint256 nu
    ) internal pure returns (uint256 size) {
        if (_shorts > 0) revert Position__InvalidAssetChange();

        if (price < self.upper) {
            size = _longs.divWad(WAD - nu);
        } else {
            size = collateralToContracts(
                _collateral.divWad(self.averagePrice()),
                self.strike,
                self.isCall
            );

            if (_longs > 0) revert Position__InvalidAssetChange();
        }
    }

    function calculateAssetChangeSellWithShorts(
        Key memory self,
        uint256 price,
        uint256 _collateral,
        uint256 _longs,
        uint256 _shorts,
        uint256 nu
    ) internal pure returns (uint256 size) {
        if (_longs > 0) revert Position__InvalidAssetChange();

        if (price > self.lower) {
            size = _shorts.divWad(nu);
        } else {
            size = collateralToContracts(
                self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS
                    ? _collateral.divWad(WAD - self.averagePrice())
                    : _collateral,
                self.strike,
                self.isCall
            );

            if (_shorts > 0) revert Position__InvalidAssetChange();
        }
    }

    function calculateAssetChange(
        Key memory self,
        uint256 currentSize,
        uint256 price,
        uint256 _collateral,
        uint256 _longs,
        uint256 _shorts
    ) internal pure returns (uint256) {
        uint256 _contracts = Math.max(_longs, _shorts);
        self.assertSatisfiesRatio(currentSize, price, _collateral, _contracts);

        uint256 nu = self.pieceWiseLinear(price);
        uint256 size;
        if (
            self.orderType == OrderType.SELL_WITH_COLLATERAL_USE_PREMIUMS ||
            self.orderType == OrderType.SELL_WITH_COLLATERAL
        ) {
            size = calculateAssetChangeSellWithCollateral(
                self,
                price,
                _collateral,
                _longs,
                _shorts,
                nu
            );
        } else if (self.orderType == OrderType.BUY_WITH_COLLATERAL) {
            size = calculateAssetChangeBuyWithCollateral(
                self,
                price,
                _collateral,
                _longs,
                _shorts,
                nu
            );
        } else if (self.orderType == OrderType.SELL_WITH_LONGS) {
            size = calculateAssetChangeSellWithLongs(
                self,
                price,
                _collateral,
                _longs,
                _shorts,
                nu
            );
        } else if (
            self.orderType == OrderType.BUY_WITH_SHORTS_USE_PREMIUMS ||
            self.orderType == OrderType.BUY_WITH_SHORTS
        ) {
            size = calculateAssetChangeSellWithShorts(
                self,
                price,
                _collateral,
                _longs,
                _shorts,
                nu
            );
        } else {
            revert Position__InvalidOrderType();
        }

        return size;
    }
}

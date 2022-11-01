// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {Math} from "@solidstate/contracts/utils/Math.sol";

import {PoolStorage} from "../pool/PoolStorage.sol";
import {Pricing} from "./Pricing.sol";
import {WadMath} from "./WadMath.sol";

/**
 * @notice Keeps track of LP positions
 *         Stores the lower and upper Ticks of a user's range order, and tracks the pro-rata exposure of the order.
 */
library Position {
    using Math for int256;
    using WadMath for uint256;
    using Position for Position.Key;

    error Position__NotEnoughCollateral();

    enum Side {
        BUY,
        SELL
    }

    // All the data used to calculate the key of the position
    struct Key {
        // The Agent that owns the exposure change of the Position
        address owner;
        // The Agent that can control modifications to the Position
        address operator;
        // The direction of the range order
        // ToDo : Rename to `side`
        Side rangeSide;
        // The lower tick normalized price of the range order
        uint256 lower;
        // The upper tick normalized price of the range order
        uint256 upper;
    }

    // All the data required to be saved in storage
    struct Data {
        // The amount of ask (bid) collateral the LP provides
        uint256 collateral;
        // The amount of long (short) contracts the LP provides
        uint256 contracts;
        // Used to track claimable fees over time
        uint256 lastFeeRate;
        // The amount of fees a user can claim now. Resets after claim
        uint256 claimableFees;
        Side side;
    }

    struct Liquidity {
        uint256 collateral;
        uint256 long;
        uint256 short;
    }

    function keyHash(Key memory self) internal pure returns (bytes32) {
        return keccak256(abi.encode(self));
    }

    function proportion(Key memory self, uint256 price)
        internal
        pure
        returns (uint256)
    {
        if (price < self.lower) return 0;
        else if (self.lower <= price && price < self.upper)
            return Pricing.proportion(self.lower, self.upper, price);
        return 1e18;
    }

    function averagePrice(Key memory self) internal pure returns (uint256) {
        return Math.average(self.lower, self.upper);
    }

    function liquidity(Key memory self, Data memory data)
        internal
        pure
        returns (uint256)
    {
        return
            data.side == Side.BUY
                ? data.collateral + data.contracts
                : data.collateral.divWad(self.averagePrice());
    }

    /**
     * @notice Returns the per-tick liquidity phi (delta) for a specific position.
     */
    function liquidityPerTick(
        Key memory self,
        Data memory data,
        uint256 minTickDistance
    ) internal pure returns (uint256) {
        uint256 amountOfTicks = Pricing.amountOfTicksBetween(
            self.lower,
            self.upper,
            minTickDistance
        );

        return self.liquidity(data) / amountOfTicks;
    }

    function transitionPrice(Key memory self, Data memory data)
        internal
        pure
        returns (uint256)
    {
        uint256 shift = data.contracts.divWad(self.liquidity(data)).mulWad(
            self.upper - self.lower
        );

        return data.side == Side.BUY ? self.lower + shift : self.upper - shift;
    }

    function bid(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);

        // Overworked to avoid numerical rounding errors
        uint256 revenue = data.side == Side.BUY
            ? (data.collateral + data.contracts).mulWad(self.averagePrice())
            : data.collateral;

        return nu.mulWad(revenue);
    }

    function ask(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);
        uint256 x = data.side == Side.BUY ? data.collateral : data.contracts;
        return (1e18 - nu).mulWad(x);
    }

    function long(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);
        uint256 x = data.side == Side.BUY ? data.collateral : data.contracts;
        return (1e18 - nu).mulWad(self.liquidity(data) - x);
    }

    function short(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);
        uint256 x = data.side == Side.BUY ? data.collateral : data.contracts;
        return nu.mulWad(x);
    }

    /**
     * @notice Represents the total amount of bid liquidity the position is holding
     * at a particular price. In other words, it is the total amount of buying
     * power the position has at the current price.
     */
    function bidLiquidity(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);
        return nu.mulWad(self.liquidity(data));
    }

    /**
     * @notice Represents the total amount of ask liquidity the position is holding
     * at a particular price. In other words, it is the total amount of
     * selling power the position has at the current price.
     *
     * Can also be computed as,
     *     total_bid(p) = ask(p) + long(p)
     */
    function askLiquidity(
        Key memory self,
        Data memory data,
        uint256 price
    ) internal pure returns (uint256) {
        uint256 nu = self.proportion(price);
        return (1e18 - nu).mulWad(self.liquidity(data));
    }

    function liquidityState() internal {
        // ToDo : Implement ?
    }
}

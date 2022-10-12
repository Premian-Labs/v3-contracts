// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {PoolStorage} from "../pool/PoolStorage.sol";

import {Math} from "./Math.sol";
import {WadMath} from "./WadMath.sol";

/**
 * @notice Keeps track of LP positions
 *         Stores the lower and upper Ticks of a user's range order, and tracks
 *         the pro-rata exposure of the order.
 *
 *         P_DL:= The price at which all long options are closed
 *         P_DS:= The price at which all short options are covered
 *
 *         C_B => DL:= C_B / P_bar(P_DL, T_lower)         (1 unit of bid collateral = (1 / P_bar) contracts of long options)
 *         C_A => DS:= C_A                                (1 unit of ask collateral = 1 contract of short options)
 *         DL => C_B:= DL * P_bar(T_lower, P_DL)          (1 unit of long options = P_bar units of bid collateral)
 *         DS => C_A:= DS * (1 - P_bar(T_upper, P_DS))    (1 contract of short options = (1 - P_bar) unit of ask collateral)
 */
library Position {
    using Math for int256;
    using WadMath for uint256;
    using Position for Position.Args;
    using Position for Position.Key;

    error Position__NotEnoughCollateral();

    struct Key {
        address owner;
        address operator;
        PoolStorage.Side rangeSide;
        uint256 lower;
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
    }

    // All the args required for the internal functions of Position
    struct Args {
        PoolStorage.Side rangeSide;
        // ToDo : Probably can use uint64
        // The lower tick normalized price of the range order
        uint256 lower;
        // The upper tick normalized price of the range order
        uint256 upper;
        // The amount of ask (bid) collateral the LP provides
        uint256 collateral;
        // The amount of long (short) contracts the LP provides
        uint256 contracts;
    }

    struct Liquidity {
        uint256 collateral;
        uint256 long;
        uint256 short;
    }

    function keyHash(Key memory self) internal pure returns (bytes32) {
        return keccak256(abi.encode(self));
    }

    function transitionPrice(Args memory self) internal pure returns (uint256) {
        if (self.rangeSide == PoolStorage.Side.BUY) {
            return
                self.upper -
                ((self.averagePrice() * self.contracts) / self.collateral)
                    .mulWad(self.upper - self.lower);
        }

        return
            self.lower +
            (self.contracts * (self.upper - self.lower)) /
            self.lambdaAsk();
    }

    function averagePrice(Args memory self) internal pure returns (uint256) {
        return (self.upper + self.lower) / 2;
    }

    function bidAveragePrice(Args memory self) internal pure returns (uint256) {
        return (self.transitionPrice() + self.lower) / 2;
    }

    function shortAveragePrice(Args memory self)
        internal
        pure
        returns (uint256)
    {
        return (self.upper + self.transitionPrice()) / 2;
    }

    /**
     * @notice The total number of long contracts that must be bought to move through this Position's range.
     */
    function lambdaBid(Args memory self) internal pure returns (uint256) {
        uint256 additionalShortCollateralRequired = self.contracts.mulWad(
            self.shortAveragePrice()
        );

        if (self.collateral < additionalShortCollateralRequired)
            revert Position__NotEnoughCollateral();

        return
            self.contracts +
            (self.collateral - additionalShortCollateralRequired).divWad(
                self.bidAveragePrice()
            );
    }

    /**
     * @notice The total number of short contracts that must be sold to move through this Position's range.
     */
    function lambdaAsk(Args memory self) internal pure returns (uint256) {
        return self.collateral + self.contracts;
    }

    function _lambda(Args memory self) internal pure returns (uint256) {
        return
            self.rangeSide == PoolStorage.Side.BUY
                ? self.lambdaBid()
                : self.lambdaAsk();
    }

    /**
     * @notice The per-tick liquidity delta for a specific position.
     */
    function phi(Args memory self, uint256 minTickDistance)
        internal
        pure
        returns (uint256)
    {
        // ToDo : Check if precision is enough
        return
            self._lambda().divWad(
                (self.upper - self.lower) * (1e18 / minTickDistance)
            );
    }
}

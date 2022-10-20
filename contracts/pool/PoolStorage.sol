// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64Token} from "@solidstate/abdk-math-extensions/contracts/ABDKMath64x64Token.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";
import {Tick} from "../libraries/Tick.sol";

import {IPoolTicks} from "./IPoolTicks.sol";

library PoolStorage {
    using ABDKMath64x64 for int128;
    using PoolStorage for PoolStorage.Layout;

    error Pool__OptionNotExpired();

    enum TokenType {
        FREE_LIQUIDITY,
        LONG,
        SHORT
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("premia.contracts.storage.Pool");

    struct Layout {
        // ERC20 token addresses
        address base;
        address underlying;
        // AggregatorV3Interface oracle addresses
        address baseOracle;
        address underlyingOracle;
        // token metadata
        uint8 underlyingDecimals;
        uint8 baseDecimals;
        uint64 maturity;
        // Whether its a call or put pool
        bool isCallPool;
        // Index of all existing ticks sorted
        LinkedList.List tickIndex;
        mapping(uint256 => Tick.Data) ticks;
        uint256 currentTickId;
        uint256 marketPrice;
        uint256 globalFeeRate;
        uint256 protocolFees;
        uint256 strike;
        uint256 liquidityRate;
        // Current tick normalized price
        uint256 tick;
        // Spot price after maturity // ToDo : Save the spot price
        uint256 spot;
        // key -> positionData
        mapping(bytes32 => Position.Data) positions;
        // owner -> operator -> positionLiquidity
        mapping(address => mapping(address => Position.Liquidity)) externalPositions;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /**
     * @notice Get the token used as options collateral and for payment of premium. (Base for PUT pools, underlying for CALL pools)
     */
    function getPoolToken(Layout storage l) internal view returns (address) {
        return l.isCallPool ? l.underlying : l.base;
    }

    function minTickDistance(Layout storage l) internal view returns (uint256) {
        return l.isCallPool ? 1e14 : l.strike / 1e4;
    }

    function getSpotPrice(Layout storage l) internal view returns (uint256) {
        if (l.spot == 0) {
            if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();

            // ToDo : Query price and save it if not yet saved
        }

        return l.spot;
    }

    /**
     * @notice calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param rangeSide The side of the range position
     * @param lower The lower bound normalized option price
     * @param upper The upper bound normalized option price
     * @return tokenId token id
     */
    function formatTokenId(
        TokenType tokenType,
        Position.Side rangeSide,
        uint64 lower,
        uint64 upper
    ) internal pure returns (uint256 tokenId) {
        tokenId =
            (uint256(upper) << 70) +
            (uint256(lower) << 6) +
            (uint256(tokenType) << 2) +
            uint256(rangeSide);
    }

    /**
     * @notice derive option maturity and strike price from ERC1155 token id
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return rangeSide The side of the range position
     * @return lower The lower bound normalized option price
     * @return upper The upper bound normalized option price
     */
    function parseTokenId(uint256 tokenId)
        internal
        pure
        returns (
            TokenType tokenType,
            Position.Side rangeSide,
            uint64 lower,
            uint64 upper
        )
    {
        assembly {
            upper := shr(70, tokenId)
            lower := shr(6, tokenId)
            tokenType := and(shr(2, tokenId), 15)
            rangeSide := and(tokenId, 3)
        }
    }
}

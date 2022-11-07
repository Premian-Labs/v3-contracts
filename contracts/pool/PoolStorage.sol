// SPDX-License-Identifier: UNLICENSED

// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";
import {Tick} from "../libraries/Tick.sol";

import {IPoolTicks} from "./IPoolTicks.sol";

library PoolStorage {
    using PoolStorage for PoolStorage.Layout;

    // ToDo : Get rid of duplicate error def
    error Pool__OptionNotExpired();

    enum TokenType {
        SHORT, // 0
        LONG // 1
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
        uint256 marketPrice;
        uint256 globalFeeRate;
        uint256 protocolFees;
        uint256 strike;
        uint256 liquidityRate;
        // Current tick normalized price
        uint256 currentTick;
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

    function getSpotPrice(Layout storage l) internal view returns (uint256) {
        if (l.spot == 0) {
            if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();

            // ToDo : Query price and save it if not yet saved
        }

        return l.spot;
    }

    /**
     * @notice calculate ERC1155 token id for given option parameters
     * @param operator The current operator of the position
     * @param rangeSide The side of the range position
     * @param lower The lower bound normalized option price
     * @param upper The upper bound normalized option price
     * @return tokenId token id
     */
    function formatTokenId(
        address operator,
        Position.Side rangeSide,
        uint64 lower,
        uint64 upper
    ) internal pure returns (uint256 tokenId) {
        // We convert upper and lower from 18 to 14 decimals, to be able to fit in 47 bits
        tokenId =
            (uint256(uint160(operator)) << 96) +
            (uint256(upper / 1e4) << 49) +
            (uint256(lower / 1e4) << 2) +
            uint256(rangeSide);
    }

    /**
     * @notice derive option maturity and strike price from ERC1155 token id
     * @param tokenId token id
     * @return operator The current operator of the position
     * @return rangeSide The side of the range position
     * @return lower The lower bound normalized option price
     * @return upper The upper bound normalized option price
     */
    function parseTokenId(uint256 tokenId)
        internal
        pure
        returns (
            address operator,
            Position.Side rangeSide,
            uint64 lower,
            uint64 upper
        )
    {
        assembly {
            operator := shr(96, tokenId)
            upper := mul(and(shr(49, tokenId), 0x7FFFFFFFFFFF), 10000) // 47 bits mask + convert from 14 decimals to 18
            lower := mul(and(shr(2, tokenId), 0x7FFFFFFFFFFF), 10000) // 47 bits mask + convert from 14 decimals to 18
            rangeSide := and(tokenId, 3) // 2 bits mask
        }
    }
}

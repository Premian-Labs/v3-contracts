// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {Position} from "../libraries/Position.sol";
import {Tick} from "../libraries/Tick.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

library PoolStorage {
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for int256;

    // Token id for SHORT
    uint256 internal constant SHORT = 0;
    // Token id for LONG
    uint256 internal constant LONG = 1;

    // The version of LP token, used to know how to decode it, if upgrades are made
    uint8 internal constant TOKEN_VERSION = 1;

    uint256 internal constant MIN_TICK_DISTANCE = 1e15; // 0.001

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
        DoublyLinkedList.Uint256List tickIndex;
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
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    /// @notice Get the token used as options collateral and for payment of premium. (Base for PUT pools, underlying for CALL pools)
    function getPoolToken(Layout storage l) internal view returns (address) {
        return l.isCallPool ? l.underlying : l.base;
    }

    function getSpotPrice(Layout storage l) internal returns (uint256 price) {
        if (l.spot == 0) {
            if (block.timestamp < l.maturity)
                revert IPoolInternal.Pool__OptionNotExpired();

            int256 basePrice = getSpotPrice(l.baseOracle);
            int256 underlyingPrice = getSpotPrice(l.underlyingOracle);

            l.spot = ((underlyingPrice * 1e18) / basePrice).toUint256();
        }

        return l.spot;
    }

    function getSpotPrice(address oracle) internal view returns (int256) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(oracle).latestRoundData();

        ensureSpotPriceValid(roundID, price, updatedAt, answeredInRound);

        return price;
    }

    function ensureSpotPriceValid(
        uint80 roundId,
        int256 price,
        uint256 updatedAt,
        uint80 answeredInRound
    ) internal view {
        // TODO: Remove hardcoded heartbeat
        if (block.timestamp - updatedAt > 25 hours)
            revert IPoolInternal.Pool__OraclePriceStale();

        if (roundId > answeredInRound)
            revert IPoolInternal.Pool__OracleRoundStale();

        if (0 >= price) revert IPoolInternal.Pool__OraclePriceLTEZero();
    }

    /// @notice calculate ERC1155 token id for given option parameters
    /// @param operator The current operator of the position
    /// @param lower The lower bound normalized option price
    /// @param upper The upper bound normalized option price
    /// @return tokenId token id
    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) internal pure returns (uint256 tokenId) {
        tokenId =
            (uint256(TOKEN_VERSION) << 252) +
            (uint256(orderType) << 180) +
            (uint256(uint160(operator)) << 20) +
            ((upper / MIN_TICK_DISTANCE) << 10) +
            (lower / MIN_TICK_DISTANCE);
    }

    /// @notice derive option maturity and strike price from ERC1155 token id
    /// @param tokenId token id
    /// @return version The version of LP token, used to know how to decode it, if upgrades are made
    /// @return operator The current operator of the position
    /// @return lower The lower bound normalized option price
    /// @return upper The upper bound normalized option price
    function parseTokenId(
        uint256 tokenId
    )
        internal
        pure
        returns (
            uint8 version,
            address operator,
            uint256 lower,
            uint256 upper,
            Position.OrderType orderType
        )
    {
        assembly {
            version := shr(252, tokenId)
            orderType := and(shr(180, tokenId), 0xF) // 4 bits mask
            operator := shr(20, tokenId)
            upper := mul(
                and(shr(10, tokenId), 0x3FF), // 10 bits mask
                MIN_TICK_DISTANCE
            )
            lower := mul(
                and(tokenId, 0x3FF), // 10 bits mask
                MIN_TICK_DISTANCE
            )
        }
    }
}

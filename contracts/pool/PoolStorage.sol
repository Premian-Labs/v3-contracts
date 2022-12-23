// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {LinkedList} from "../libraries/LinkedList.sol";
import {Position} from "../libraries/Position.sol";
import {Tick} from "../libraries/Tick.sol";

import {IPoolTicks} from "./IPoolTicks.sol";

library PoolStorage {
    using PoolStorage for PoolStorage.Layout;

    // ToDo : Get rid of duplicate error def
    error Pool__OptionNotExpired();

    // Token id for SHORT
    uint256 internal constant SHORT = 0;
    // Token id for LONG
    uint256 internal constant LONG = 1;

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

    function getSpotPrice(Layout storage l) internal view returns (uint256) {
        if (l.spot == 0) {
            if (block.timestamp < l.maturity) revert Pool__OptionNotExpired();

            // ToDo : Query price and save it if not yet saved
        }

        return l.spot;
    }

    /// @notice calculate ERC1155 token id for given option parameters
    /// @param operator The current operator of the position
    /// @param lower The lower bound normalized option price
    /// @param upper The upper bound normalized option price
    /// @return tokenId token id
    function formatTokenId(
        address operator,
        uint16 lower,
        uint16 upper,
        Position.OrderType orderType
    ) internal pure returns (uint256 tokenId) {
        // ToDo : Add safeguard to prevent SHORT / LONG token id to be used (0 / 1)
        tokenId =
            (uint256(orderType) << 188) +
            (uint256(uint160(operator)) << 28) +
            (uint256(upper) << 14) +
            uint256(lower);
    }

    /// @notice derive option maturity and strike price from ERC1155 token id
    /// @param tokenId token id
    /// @return operator The current operator of the position
    /// @return lower The lower bound normalized option price
    /// @return upper The upper bound normalized option price
    function parseTokenId(
        uint256 tokenId
    )
        internal
        pure
        returns (
            address operator,
            uint16 lower,
            uint16 upper,
            Position.OrderType orderType
        )
    {
        assembly {
            orderType := shr(188, tokenId)
            operator := and(
                shr(28, tokenId),
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF // 160 bits mask
            )
            upper := and(shr(14, tokenId), 0x3FFF) // 14 bits mask
            lower := and(tokenId, 0x3FFF) // 14 bits mask
        }
    }
}

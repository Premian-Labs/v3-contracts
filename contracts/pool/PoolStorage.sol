// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {AggregatorInterface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorInterface.sol";
import {DoublyLinkedList} from "@solidstate/contracts/data/DoublyLinkedList.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {UD60x18} from "../libraries/prbMath/UD60x18.sol";
import {Position} from "../libraries/Position.sol";
import {OptionMath} from "../libraries/OptionMath.sol";

import {IOracleAdapter} from "../oracle/price/IOracleAdapter.sol";

import {IPoolInternal} from "./IPoolInternal.sol";

library PoolStorage {
    using PoolStorage for PoolStorage.Layout;
    using SafeCast for int256;
    using UD60x18 for uint256;

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
        address quote;
        address oracleAdapter;
        // token metadata
        // TODO: Remove if not used
        uint8 baseDecimals;
        // TODO: Remove if not used
        uint8 quoteDecimals;
        uint64 maturity;
        // Whether its a call or put pool
        bool isCallPool;
        // Index of all existing ticks sorted
        DoublyLinkedList.Uint256List tickIndex;
        mapping(uint256 => IPoolInternal.Tick) ticks;
        uint256 marketPrice;
        uint256 globalFeeRate;
        uint256 protocolFees;
        uint256 strike;
        uint256 liquidityRate;
        uint256 longRate;
        uint256 shortRate;
        // Current tick normalized price
        uint256 currentTick;
        // Spot price after maturity // ToDo : Save the spot price
        uint256 spot;
        // key -> positionData
        mapping(bytes32 => Position.Data) positions;
        // Size of quotes already filled (provider -> quoteHash -> amountFilled)
        mapping(address => mapping(bytes32 => uint256)) tradeQuoteAmountFilled;
        // Set to true after maturity, to handle factory initialization discount
        bool hasRemoved;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function getPoolTokenDecimals(
        Layout storage l
    ) internal view returns (uint8) {
        return l.isCallPool ? l.baseDecimals : l.quoteDecimals;
    }

    /// @notice Adjust decimals of a value to match the pool token decimals
    function scaleDecimals(
        Layout storage l,
        uint256 value
    ) internal view returns (uint256) {
        uint256 decimals = l.getPoolTokenDecimals();
        return OptionMath.scaleDecimals(value, decimals);
    }

    /// @notice Get the token used as options collateral and for payment of premium. (quote for PUT pools, base for CALL pools)
    function getPoolToken(Layout storage l) internal view returns (address) {
        return l.isCallPool ? l.base : l.quote;
    }

    // TODO: Fetch price at maturity
    function fetchQuote(Layout storage l) internal returns (uint256) {
        if (l.spot == 0) {
            if (block.timestamp < l.maturity)
                revert IPoolInternal.Pool__OptionNotExpired();

            l.spot = IOracleAdapter(l.oracleAdapter).quote(l.base, l.quote);
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

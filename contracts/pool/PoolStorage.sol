// SPDX-License-Identifier: BUSL-1.1
// For further clarification please see https://license.premia.legal

pragma solidity ^0.8.0;

import {ABDKMath64x64Token} from "@solidstate/abdk-math-extensions/contracts/ABDKMath64x64Token.sol";
import {ABDKMath64x64} from "abdk-libraries-solidity/ABDKMath64x64.sol";

import {LinkedList} from "../libraries/LinkedList.sol";
import {Tick} from "../libraries/Tick.sol";

import {IPoolTicks} from "./IPoolTicks.sol";

library PoolStorage {
    using ABDKMath64x64 for int128;
    using PoolStorage for PoolStorage.Layout;

    enum TokenType {
        FREE_LIQUIDITY,
        LONG,
        SHORT
    }

    // ToDo : Move somewhere else ?
    enum TradeSide {
        BUY,
        SELL
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
        // Whether its a call or put pool
        bool isCallPool;
        // Index of all existing ticks sorted
        LinkedList.List tickIndex;
        mapping(uint256 => Tick.Data) ticks;
        uint256 currentTickId;
        uint256 marketPrice;
        uint256 globalFeesPerLiq;
        uint256 strike;
        uint256 liq;
    }

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }

    function minTickDistance(Layout storage l) internal view returns (uint256) {
        return l.isCallPool ? 1e14 : l.strike / 1e4;
    }

    /**
     * @notice calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param maturity timestamp of option maturity
     * @param strike64x64 64x64 fixed point representation of strike price
     * @return tokenId token id
     */
    function formatTokenId(
        TokenType tokenType,
        uint64 maturity,
        int128 strike64x64
    ) internal pure returns (uint256 tokenId) {
        tokenId =
            (uint256(tokenType) << 248) +
            (uint256(maturity) << 128) +
            uint256(int256(strike64x64));
    }

    /**
     * @notice derive option maturity and strike price from ERC1155 token id
     * @param tokenId token id
     * @return tokenType TokenType enum
     * @return maturity timestamp of option maturity
     * @return strike64x64 option strike price
     */
    function parseTokenId(uint256 tokenId)
        internal
        pure
        returns (
            TokenType tokenType,
            uint64 maturity,
            int128 strike64x64
        )
    {
        assembly {
            tokenType := shr(248, tokenId)
            maturity := shr(128, tokenId)
            strike64x64 := tokenId
        }
    }
}

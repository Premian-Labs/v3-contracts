// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;
import {UD60x18} from "@prb/math/UD60x18.sol";

import {IMiningPool} from "../../mining/IMiningPool.sol";
import {MiningPool} from "../../mining/MiningPool.sol";
import {MiningPoolStorage} from "../../mining/MiningPoolStorage.sol";

contract MiningPoolMock is MiningPool {
    constructor(address treasury, UD60x18 treasuryFee) MiningPool(treasury, treasuryFee) {}

    function formatTokenId(
        IMiningPool.TokenType tokenType,
        uint64 maturity,
        UD60x18 strike
    ) external pure returns (uint256 tokenId) {
        return MiningPoolStorage.formatTokenId(tokenType, maturity, strike);
    }

    function parseTokenId(
        uint256 tokenId
    ) external pure returns (IMiningPool.TokenType tokenType, uint64 maturity, int128 strike) {
        return MiningPoolStorage.parseTokenId(tokenId);
    }
}

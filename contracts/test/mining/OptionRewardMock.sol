// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;
import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOptionReward} from "../../mining/IOptionReward.sol";
import {OptionReward} from "../../mining/OptionReward.sol";
import {OptionRewardStorage} from "../../mining/OptionRewardStorage.sol";

contract OptionRewardMock is OptionReward {
    constructor(address treasury, UD60x18 treasuryFee) OptionReward(treasury, treasuryFee) {}

    function formatTokenId(
        IOptionReward.TokenType tokenType,
        uint64 maturity,
        UD60x18 strike
    ) external pure returns (uint256 tokenId) {
        return OptionRewardStorage.formatTokenId(tokenType, maturity, strike);
    }

    function parseTokenId(
        uint256 tokenId
    ) external pure returns (IOptionReward.TokenType tokenType, uint64 maturity, int128 strike) {
        return OptionRewardStorage.parseTokenId(tokenId);
    }
}

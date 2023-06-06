// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";
import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";
import {ERC1155Base} from "@solidstate/contracts/token/ERC1155/base/ERC1155Base.sol";
import {ERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseInternal.sol";
import {ERC1155BaseStorage} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseStorage.sol";
import {ERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {OptionMath} from "../libraries/OptionMath.sol";

import {IMiningPool} from "./IMiningPool.sol";
import {IPriceRepository} from "./IPriceRepository.sol";
import {MiningPoolStorage} from "./MiningPoolStorage.sol";

import "forge-std/console2.sol";

contract MiningPool is ERC1155Base, ERC1155Enumerable, ERC165Base, IMiningPool, ReentrancyGuard {
    using SafeCast for int256;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    // caller must approve token
    function writeFrom(address underwriter, address longReceiver, uint256 size) external nonReentrant {
        if (
            msg.sender != underwriter && ERC1155BaseStorage.layout().operatorApprovals[underwriter][msg.sender] == false
        ) revert MiningPool__OperatorNotAuthorized(msg.sender);

        MiningPoolStorage.Layout storage l = MiningPoolStorage.layout();
        IERC20(l.base).safeTransferFrom(underwriter, address(this), size);

        uint256 timestamp8AMUTC = OptionMath.calculateTimestamp8AMUTC(block.timestamp);
        uint64 maturity = (timestamp8AMUTC + l.daysToExpiry).toUint64();

        UD60x18 spot = IPriceRepository(l.priceRepository).getDailyOpenPriceFrom(l.base, l.quote, timestamp8AMUTC);
        int256 strike = OptionMath.roundToNearestTenth(spot * l.percentOfSpot).unwrap().toInt256();

        uint256 longTokenId = formatTokenId(TokenType.LONG, maturity, strike.toInt128());
        uint256 shortTokenId = formatTokenId(TokenType.SHORT, maturity, strike.toInt128());

        _mint(longReceiver, longTokenId, size, "");
        _mint(underwriter, shortTokenId, size, "");

        emit WriteFrom(underwriter, longReceiver, size, strike, maturity);
    }

    function exercise() external nonReentrant {}

    function settle() external nonReentrant {}

    /**
     * @notice Calculate ERC1155 token id for given option parameters
     * @param tokenType TokenType enum
     * @param maturity Timestamp of option maturity
     * @param strike Strike price
     * @return tokenId Token id
     */
    function formatTokenId(TokenType tokenType, uint64 maturity, int128 strike) public pure returns (uint256 tokenId) {
        tokenId = (uint256(tokenType) << 248) + (uint256(maturity) << 128) + uint256(int256(strike));
    }

    /**
     * @notice Derive option maturity and strike price from ERC1155 token id
     * @param tokenId Token id
     * @return tokenType TokenType enum
     * @return maturity Timestamp of option maturity
     * @return strike Option strike price
     */
    function parseTokenId(uint256 tokenId) public pure returns (TokenType tokenType, uint64 maturity, int128 strike) {
        assembly {
            tokenType := shr(248, tokenId)
            maturity := shr(128, tokenId)
            strike := tokenId
        }
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155BaseInternal, ERC1155EnumerableInternal) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}

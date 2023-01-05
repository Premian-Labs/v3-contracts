// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {ERC165Base} from "@solidstate/contracts/introspection/ERC165/base/ERC165Base.sol";
import {ERC1155Base} from "@solidstate/contracts/token/ERC1155/base/ERC1155Base.sol";
import {ERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/ERC1155BaseInternal.sol";
import {ERC1155Enumerable} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155Enumerable.sol";
import {ERC1155EnumerableInternal} from "@solidstate/contracts/token/ERC1155/enumerable/ERC1155EnumerableInternal.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {Multicall} from "@solidstate/contracts/utils/Multicall.sol";

import {PoolStorage} from "./PoolStorage.sol";
import {PoolInternal} from "./PoolInternal.sol";
import {Position} from "../libraries/Position.sol";
import {IPoolCore} from "./IPoolCore.sol";

// ToDo : Add IPool inheritance
contract PoolCore is
    IPoolCore,
    PoolInternal,
    ERC1155Base,
    ERC1155Enumerable,
    ERC165Base,
    Multicall
{
    /// @notice see IPoolBase; inheritance not possible due to linearization issues
    function name() external view returns (string memory) {
        PoolStorage.Layout storage l = PoolStorage.layout();

        // ToDo : Differentiate name if a pool already exists with other oracles for this pair ?

        return
            string(
                abi.encodePacked(
                    IERC20Metadata(l.underlying).symbol(),
                    " / ",
                    IERC20Metadata(l.base).symbol(),
                    " - Premia Options Pool"
                )
            );
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    )
        internal
        virtual
        override(ERC1155BaseInternal, ERC1155EnumerableInternal)
    {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function getQuote(
        uint256 size,
        bool isBuy
    ) external view returns (uint256) {
        return _getQuote(size, isBuy);
    }

    function claim(Position.Key memory p) external {
        _claim(p);
    }

    function deposit(
        Position.Key memory p,
        Position.OrderType orderType,
        uint256 belowLower,
        uint256 belowUpper,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) external {
        _deposit(
            p,
            orderType,
            belowLower,
            belowUpper,
            collateral,
            longs,
            shorts
        );
    }

    function withdraw(
        Position.Key memory p,
        uint256 collateral,
        uint256 longs,
        uint256 shorts
    ) external {
        _withdraw(p, collateral, longs, shorts);
    }

    function trade(uint256 size, bool isBuy) external returns (uint256) {
        return _trade(msg.sender, size, isBuy);
    }

    function annihilate(uint256 size) external {
        _annihilate(msg.sender, size);
    }

    function exercise() external returns (uint256) {
        return _exercise(msg.sender);
    }

    function settle() external returns (uint256) {
        return _settle(msg.sender);
    }

    function settlePosition(Position.Key memory p) external returns (uint256) {
        return _settlePosition(p);
    }

    function getNearestTickBelow(
        uint256 price
    ) external view returns (uint256) {
        return _getNearestTickBelow(price);
    }
}

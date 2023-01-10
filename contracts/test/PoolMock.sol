// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

import {Position} from "../libraries/Position.sol";
import {Pricing} from "../libraries/Pricing.sol";

import {PoolCore} from "../pool/PoolCore.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";
import {_IPoolMock} from "./_IPoolMock.sol";

contract PoolMock is _IPoolMock, PoolCore {
    using PoolStorage for PoolStorage.Layout;

    constructor(
        address exchangeHelper,
        address wrappedNativeToken
    ) PoolCore(exchangeHelper, wrappedNativeToken) {}

    function formatTokenId(
        address operator,
        uint256 lower,
        uint256 upper,
        Position.OrderType orderType
    ) external pure returns (uint256 tokenId) {
        return PoolStorage.formatTokenId(operator, lower, upper, orderType);
    }

    function parseTokenId(
        uint256 tokenId
    )
        external
        pure
        returns (
            uint8 version,
            address operator,
            uint256 lower,
            uint256 upper,
            Position.OrderType orderType
        )
    {
        return PoolStorage.parseTokenId(tokenId);
    }

    // ToDo : Move to PricingMock ?
    function amountOfTicksBetween(
        uint256 lower,
        uint256 upper
    ) external pure returns (uint256) {
        return Pricing.amountOfTicksBetween(lower, upper);
    }
}

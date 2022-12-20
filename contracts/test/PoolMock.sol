// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import {OwnableStorage} from "@solidstate/contracts/access/ownable/OwnableStorage.sol";
import {ERC165Storage} from "@solidstate/contracts/introspection/ERC165Storage.sol";
import {SolidStateERC20} from "@solidstate/contracts/token/ERC20/SolidStateERC20.sol";
import {ERC20MetadataStorage} from "@solidstate/contracts/token/ERC20/metadata/ERC20MetadataStorage.sol";

import {Position} from "../libraries/Position.sol";
import {Pool} from "../pool/Pool.sol";
import {PoolStorage} from "../pool/PoolStorage.sol";

contract PoolMock is Pool {
    using PoolStorage for PoolStorage.Layout;

    function formatTokenId(
        address operator,
        uint16 lower,
        uint16 upper
    ) external pure returns (uint256 tokenId) {
        return PoolStorage.formatTokenId(operator, lower, upper);
    }

    function parseTokenId(
        uint256 tokenId
    ) external pure returns (address operator, uint16 lower, uint16 upper) {
        return PoolStorage.parseTokenId(tokenId);
    }
}

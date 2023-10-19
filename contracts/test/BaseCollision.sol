// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library BaseCollisionStorage {
    bytes32 internal constant STORAGE_SLOT = keccak256("contracts.storage.BaseStorage");
}

contract BaseCollision {}

// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import {IPoolMock} from "../../../pool/mock/IPoolMock.sol";

import {UnderwriterVaultTest} from "./_UnderwriterVault.t.sol";

contract UnderwriterVaultCallTest is UnderwriterVaultTest {
    function setUp() public override {
        super.setUp();

        isCallTest = true;
        poolKey.isCallPool = true;
        pool = IPoolMock(factory.deployPool(poolKey));
        vault = callVault;
    }
}

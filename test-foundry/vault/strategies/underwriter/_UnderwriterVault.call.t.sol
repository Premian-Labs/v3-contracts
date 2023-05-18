// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {UnderwriterVaultTest} from "./_UnderwriterVault.t.sol";

contract UnderwriterVaultCallTest is UnderwriterVaultTest {
    function setUp() public override {
        super.setUp();

        poolKey.isCallPool = true;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
    }
}

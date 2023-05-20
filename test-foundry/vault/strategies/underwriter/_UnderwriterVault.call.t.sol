// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IPoolMock} from "contracts/test/pool/IPoolMock.sol";

import {UnderwriterVaultTest} from "./_UnderwriterVault.t.sol";

contract UnderwriterVaultCallTest is UnderwriterVaultTest {
    function setUp() public override {
        super.setUp();

        isCallTest = true;
        poolKey.isCallPool = true;
        pool = IPoolMock(factory.deployPool{value: 1 ether}(poolKey));
        vault = callVault;
    }
}

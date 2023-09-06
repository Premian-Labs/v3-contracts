// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {Base_Test} from "../../Base.t.sol";

abstract contract Integration_Test is Base_Test {
    function setUp() public virtual override {
        Base_Test.setUp();

        // Deploy V3 Core
        deployCore();

        // Make the Admin the default caller in this test suite
        vm.startPrank({msgSender: users.deployer});

        // Approve V3 Core to spend assets from the users
        approveProtocol();
    }
}

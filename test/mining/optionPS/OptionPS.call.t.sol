// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {OptionPSTest} from "./OptionPS.t.sol";

import {IOptionPSFactory} from "contracts/mining/optionPS/IOptionPSFactory.sol";
import {OptionPS} from "contracts/mining/optionPS/OptionPS.sol";

contract OptionPSCallTest is OptionPSTest {
    function setUp() public override {
        super.setUp();

        isCall = true;

        option = OptionPS(
            optionPSFactory.deployProxy(
                IOptionPSFactory.OptionPSArgs({base: address(base), quote: address(quote), isCall: isCall})
            )
        );

        _mintTokensAndApprove();
    }
}

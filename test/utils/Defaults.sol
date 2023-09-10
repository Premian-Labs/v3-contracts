// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Constants} from "./Constants.sol";
import {Users} from "./Types.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

/// @notice Contract with default values used throughout the tests.
contract Defaults is Constants {
    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/
    uint128 public constant DEPOSIT_AMOUNT = 10_000e18;
    uint40 public immutable START_TIME;
    uint40 public immutable END_TIME;
    uint40 public constant TOTAL_DURATION = 10_000 seconds;
    uint128 public constant WITHDRAW_AMOUNT = 2600e18;

    /*//////////////////////////////////////////////////////////////////////////
                                     VARIABLES
    //////////////////////////////////////////////////////////////////////////*/
    IERC20 private base;
    IERC20 private quote;
    Users private users;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor() {
        START_TIME = uint40(MAY_1_2023) + 2 days;
        END_TIME = START_TIME + TOTAL_DURATION;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function setBase(IERC20 base_) public {
        base = base_;
    }

    function setQuote(IERC20 quote_) public {
        quote = quote_;
    }

    function setUsers(Users memory users_) public {
        users = users_;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      STRUCTS
    //////////////////////////////////////////////////////////////////////////*/
    /// Place to create default objects for tests
}

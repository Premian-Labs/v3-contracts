// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

struct Users {
    // Deployer
    address payable deployer;
    // Default admin for all Premia v3 contracts.
    address payable admin;
    // Impartial user.
    address payable alice;
    // Malicious user.
    address payable eve;
    // Default trader.
    address payable trader;
    // Default liquidity provider.
    address payable lp;
    // Default referrer
    address payable referrer;
    // Default operator
    address payable operator;
    // Default caller
    address payable caller;
    // Default receiver
    address payable receiver;
    // Default underwriter for options
    address payable underwriter;
    // Default for user that has no funds (meaning no base or quote)
    address payable broke;
    // Relayer
    address payable relayer;
}

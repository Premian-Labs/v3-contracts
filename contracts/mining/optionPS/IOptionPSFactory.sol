// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

import {IOptionPS} from "../optionPS/IOptionPS.sol";

interface IOptionPSFactory {
    event ProxyDeployed(
        address indexed base,
        address indexed quote,
        bool isCall,
        address priceRepository,
        uint256 exerciseDuration,
        address proxy
    );

    struct OptionPSArgs {
        address base;
        address quote;
        bool isCall;
        address priceRepository;
        uint256 exerciseDuration;
    }

    function isProxyDeployed(address proxy) external view returns (bool);

    function getProxyAddress(OptionPSArgs calldata args) external view returns (address, bool);

    function deployProxy(OptionPSArgs calldata args) external returns (address);
}

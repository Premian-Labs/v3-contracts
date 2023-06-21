// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {UD60x18} from "@prb/math/UD60x18.sol";

interface IOptionRewardFactory {
    event ProxyDeployed(
        address base,
        address quote,
        address underwriter,
        address priceRepository,
        address paymentSplitter,
        UD60x18 discount,
        UD60x18 penalty,
        uint256 expiryDuration,
        uint256 exerciseDuration,
        uint256 lockupDuration
    );

    struct OptionRewardArgs {
        address base;
        address quote;
        address underwriter;
        address priceRepository;
        address paymentSplitter;
        UD60x18 discount;
        UD60x18 penalty;
        uint256 expiryDuration;
        uint256 exerciseDuration;
        uint256 lockupDuration;
    }

    function isProxyDeployed(address proxy) external view returns (bool);

    function getProxyAddress(OptionRewardArgs calldata args) external view returns (address, bool);

    function deployProxy(OptionRewardArgs calldata args) external returns (address);
}

// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

interface IPaymentSplitter {
    function pay(uint256 premiaAmount, uint256 usdcAmount) external;
}

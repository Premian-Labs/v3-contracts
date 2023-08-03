// SPDX-License-Identifier: LGPL-3.0-or-later
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity ^0.8.19;

interface IPaymentSplitter {
    function pay(uint256 baseAmount, uint256 quoteAmount) external;
}

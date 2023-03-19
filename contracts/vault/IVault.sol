// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IVault {
    event UpdateQuotes();

    event Deposit(
        address indexed sender,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event Trade(
        address indexed user,
        address indexed pool,
        uint256 size,
        bool isBuy,
        uint256 premium,
        uint256 takerFeePaid,
        uint256 makerRebateReceived,
        uint256 protocolFee
    );

    event ManagementFeePaid(address indexed receiver, uint256 managementFee);

    event PerformanceFeePaid(address indexed receiver, uint256 performanceFee);

    function getTradeQuote(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external view returns (uint256 maxSize, uint256 price);

    function trade(
        uint256 strike,
        uint64 maturity,
        bool isCall,
        uint256 size,
        bool isBuy
    ) external;
}

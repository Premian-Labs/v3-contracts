pragma solidity ^0.8.0;


import "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";


contract IUnderwriterVault is SolidStateERC4626 {

    // @notice Facilitates the purchase of an option for a LT
    // @param taker The LT that is buying the option
    // @param strike The strike price the option
    // @param maturity The maturity of the option
    // @param size The number of contracts
    // @return The premium paid for this option.
    function buy(
        address taker,
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) external view returns (uint256 premium);

    // @notice Settle all positions that are past their maturity.
    function settle() external returns (uint256);

}

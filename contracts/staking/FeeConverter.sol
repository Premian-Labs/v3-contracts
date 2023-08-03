// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IExchangeHelper} from "../utils/IExchangeHelper.sol";

import {FeeConverterStorage} from "./FeeConverterStorage.sol";
import {IFeeConverter} from "./IFeeConverter.sol";
import {IVxPremia} from "./IVxPremia.sol";

/// @author Premia
/// @title A contract receiving all protocol fees, swapping them for premia
contract FeeConverter is IFeeConverter, OwnableInternal, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address private immutable EXCHANGE_HELPER;
    address private immutable USDC;
    address private immutable VXPREMIA;

    // The treasury address which will receive a portion of the protocol fees
    address private immutable TREASURY;
    // The percentage of protocol fees the treasury will get
    UD60x18 private constant TREASURY_SHARE = UD60x18.wrap(0.5e18); // 50%

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    modifier onlyAuthorized() {
        if (!FeeConverterStorage.layout().isAuthorized[msg.sender]) revert FeeConverter__NotAuthorized();
        _;
    }

    constructor(address exchangeHelper, address usdc, address vxPremia, address treasury) {
        EXCHANGE_HELPER = exchangeHelper;
        USDC = usdc;
        VXPREMIA = vxPremia;
        TREASURY = treasury;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    receive() external payable {}

    /// @inheritdoc IFeeConverter
    function getExchangeHelper() external view returns (address exchangeHelper) {
        exchangeHelper = EXCHANGE_HELPER;
    }

    ///////////
    // Admin //
    ///////////

    /// @notice Set authorization for address to use the convert function
    /// @param account The account for which to set new authorization status
    /// @param isAuthorized Whether the account is authorized or not
    function setAuthorized(address account, bool isAuthorized) external onlyOwner {
        FeeConverterStorage.layout().isAuthorized[account] = isAuthorized;

        emit SetAuthorized(account, isAuthorized);
    }

    //////////////////////////

    /// @inheritdoc IFeeConverter
    function convert(
        address sourceToken,
        address callee,
        address allowanceTarget,
        bytes calldata data
    ) external nonReentrant onlyAuthorized {
        uint256 amount = IERC20(sourceToken).balanceOf(address(this));

        if (amount == 0) return;

        uint256 outAmount;

        if (sourceToken == USDC) {
            outAmount = amount;
        } else {
            IERC20(sourceToken).safeTransfer(EXCHANGE_HELPER, amount);

            (outAmount, ) = IExchangeHelper(EXCHANGE_HELPER).swapWithToken(
                sourceToken,
                USDC,
                amount,
                callee,
                allowanceTarget,
                data,
                address(this)
            );
        }

        uint256 treasuryAmount = (ud(outAmount) * TREASURY_SHARE).unwrap();

        IERC20(USDC).safeTransfer(TREASURY, treasuryAmount);
        IERC20(USDC).approve(VXPREMIA, outAmount - treasuryAmount);
        IVxPremia(VXPREMIA).addRewards(outAmount - treasuryAmount);

        emit Converted(msg.sender, sourceToken, amount, outAmount, treasuryAmount);
    }
}

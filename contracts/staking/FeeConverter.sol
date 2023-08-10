// SPDX-License-Identifier: LicenseRef-P3-DUAL
// For terms and conditions regarding commercial use please see https://license.premia.blue
pragma solidity =0.8.19;

import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@solidstate/contracts/interfaces/IERC4626.sol";
import {ReentrancyGuard} from "@solidstate/contracts/security/reentrancy_guard/ReentrancyGuard.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {ONE} from "../libraries/Constants.sol";
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
    address private immutable VX_PREMIA;

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    modifier onlyAuthorized() {
        if (!FeeConverterStorage.layout().isAuthorized[msg.sender]) revert FeeConverter__NotAuthorized();
        _;
    }

    modifier isInitialized() {
        if (FeeConverterStorage.layout().treasury == address(0)) revert FeeConverter__NotInitialized();
        _;
    }

    constructor(address exchangeHelper, address usdc, address vxPremia) {
        EXCHANGE_HELPER = exchangeHelper;
        USDC = usdc;
        VX_PREMIA = vxPremia;
    }

    //////////////////////////////////////////////////
    //////////////////////////////////////////////////
    //////////////////////////////////////////////////

    receive() external payable {}

    /// @inheritdoc IFeeConverter
    function getExchangeHelper() external view returns (address exchangeHelper) {
        exchangeHelper = EXCHANGE_HELPER;
    }

    /// @inheritdoc IFeeConverter
    function getTreasury() external view returns (address treasury, UD60x18 treasuryShare) {
        FeeConverterStorage.Layout storage l = FeeConverterStorage.layout();
        return (l.treasury, l.treasuryShare);
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

    /// @notice Set a new treasury address, and its share (The % of funds allocated to the `treasury` address)
    function setTreasury(address newTreasury, UD60x18 newTreasuryShare) external onlyOwner {
        if (newTreasuryShare > ONE) revert FeeConverter__TreasuryShareGreaterThanOne();

        FeeConverterStorage.Layout storage l = FeeConverterStorage.layout();
        l.treasury = newTreasury;
        l.treasuryShare = newTreasuryShare;

        emit SetTreasury(newTreasury, newTreasuryShare);
    }

    //////////////////////////

    /// @inheritdoc IFeeConverter
    function convert(
        address sourceToken,
        address callee,
        address allowanceTarget,
        bytes calldata data
    ) external isInitialized nonReentrant onlyAuthorized {
        FeeConverterStorage.Layout storage l = FeeConverterStorage.layout();
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

        if (outAmount == 0) return;

        uint256 treasuryAmount = (ud(outAmount) * l.treasuryShare).unwrap();
        uint256 vxPremiaAmount = outAmount - treasuryAmount;

        if (treasuryAmount > 0) {
            IERC20(USDC).safeTransfer(l.treasury, treasuryAmount);
        }

        if (vxPremiaAmount > 0) {
            IERC20(USDC).approve(VX_PREMIA, vxPremiaAmount);
            IVxPremia(VX_PREMIA).addRewards(vxPremiaAmount);
        }

        emit Converted(msg.sender, sourceToken, amount, outAmount, treasuryAmount);
    }

    /// @inheritdoc IFeeConverter
    function redeem(
        address vault,
        uint256 shareAmount
    ) external isInitialized nonReentrant onlyAuthorized returns (uint256 assetAmount) {
        return IERC4626(vault).redeem(shareAmount, address(this), address(this));
    }
}

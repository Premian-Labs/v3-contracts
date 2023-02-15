// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@solidstate/contracts/token/ERC4626/base/ERC4626BaseStorage.sol";
import "@solidstate/contracts/token/ERC4626/SolidStateERC4626.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@solidstate/contracts/utils/SafeERC20.sol";
import {OwnableInternal} from "@solidstate/contracts/access/ownable/OwnableInternal.sol"; 

import "./IUnderwriterVault.sol";
import {UnderwriterVaultStorage} from "./UnderwriterVaultStorage.sol";
import {IVolatilityOracle} from "../../oracle/IVolatilityOracle.sol";
import {OptionMath} from "../../libraries/OptionMath.sol";


contract UnderwriterVault is IUnderwriterVault, SolidStateERC4626, OwnableInternal {
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;
    using SafeERC20 for IERC20;

    error Vault__InsufficientFunds();
    error Vault__OptionExpired();
    error Vault__OptionPoolNotListed();
    error Vault__OptionPoolNotSupported();

    // Instance Variables
    // isCall : bool
    // listings : 
    address internal immutable ORACLE;


    constructor (address oracleAddress) {
        ORACLE = oracleAddress;
    }


    function setVariable(uint256 value) external onlyOwner {
        UnderwriterVaultStorage.layout().variable = value;
    } 

    function _asset() override internal view virtual returns (address) {
        return ERC4626BaseStorage.layout().asset;
    }

    function _totalAssets() override internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalAssets;
    }

    function _totalLockedSpread() internal view returns (uint256) {
        // total assets = deposits + premiums + spreads
        return UnderwriterVaultStorage.layout().totalLockedSpread;
    }

    function _fairValue() internal view returns (uint256) {
        // todo
        // store efficiently a list of strikes and maturities underwritten
        return 0;
    }

    // @notice updates total spread in storage to be able to compute the price per share
    //
    function _updateVars() internal {
        UnderwriterVaultStorage.Layout storage layout = UnderwriterVaultStorage.layout();

        uint256 lastMaturity = layout.lastMaturity;
        uint256 nextMaturity = layout.nextMaturities[lastMaturity];
        uint256 lastSpreadUnlockUpdate = layout.lastSpreadUnlockUpdate;
        uint256 spreadUnlockingRate = layout.spreadUnlockingRate;
        uint256 totalLockedSpread = layout.totalLockedSpread;

        uint256 totalAssets = _totalAssets();
        uint256 totalLockedSpread = layout.deadlineToWithdrawAmount;

        while (block.timestamp >= nextMaturity) {
            totalLockedSpread -= (nextMaturity - lastSpreadUnlockUpdate) * spreadUnlockingRate;
            spreadUnlockingRate -= layout.spreadUnlockingTicks[nextMaturity];
            lastSpreadUnlockUpdate = nextMaturity;
            nextMaturity = layout.nextMaturities[nextMaturity];
        }
        totalLockedSpread -= (block.timestamp - lastSpreadUnlockUpdate) * spreadUnlockingRate;
        layout.totalLockedSpread = totalLockedSpread;
        layout.spreadUnlockingRate = spreadUnlockingRate;
        layout.lastSpreadUnlockUpdate = block.timestamp;
    }

    function _pricePerShare() internal view returns (uint256) {
        uint256 totalAssets = _totalAssets();
        uint256 supply = _totalSupply();
        uint256 fairValue = _fairValue();
        uint256 totalLockedSpread = _totalLockedSpread();

        return (totalAssets - totalLockedSpread - fairValue) / supply;
    }

    function _convertToShares(
        uint256 assetAmount
    ) override internal view returns (uint256 shareAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            shareAmount = assetAmount;
        } else {
            uint256 totalAssets = _totalAssets();
            if (totalAssets == 0) {
                shareAmount = assetAmount;
            } else {
                shareAmount = assetAmount / _pricePerShare();
            }
        }
    }

    function _convertToAssets(
        uint256 shareAmount
    ) override internal view virtual returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            assetAmount = shareAmount;
        } else {
            assetAmount = shareAmount * _pricePerShare();
        }
    }

    function _maxDeposit(
        address
    ) override internal view virtual returns (uint256 maxAssets) {
        maxAssets = type(uint256).max;
    }

    function _maxMint(
        address
    ) override internal view virtual returns (uint256 maxShares) {
        maxShares = type(uint256).max;
    }

    function _maxWithdraw(
        address owner
    ) override internal view virtual returns (uint256 maxAssets) {
        maxAssets = _convertToAssets(_balanceOf(owner));
    }

    function _maxRedeem(
        address owner
    ) override internal view virtual returns (uint256 maxShares) {
        maxShares = _balanceOf(owner);
    }

    function _previewDeposit(
        uint256 assetAmount
    ) override  internal view virtual returns (uint256 shareAmount) {
        shareAmount = _convertToShares(assetAmount);
    }

    function _previewMint(
        uint256 shareAmount
    ) override internal view virtual returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            assetAmount = shareAmount;
        } else {
            assetAmount = (shareAmount * _totalAssets() + supply - 1) / supply;
        }
    }

    function _previewWithdraw(
        uint256 assetAmount
    ) override internal view virtual returns (uint256 shareAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            shareAmount = assetAmount;
        } else {
            uint256 totalAssets = _totalAssets();

            if (totalAssets == 0) {
                shareAmount = assetAmount;
            } else {
                shareAmount =
                (assetAmount * supply + totalAssets - 1) /
                totalAssets;
            }
        }
    }

    function _previewRedeem(
        uint256 shareAmount
    ) override internal view virtual returns (uint256 assetAmount) {
        assetAmount = _convertToAssets(shareAmount);
    }

    function _deposit(
        uint256 assetAmount,
        address receiver
    ) override internal virtual returns (uint256 shareAmount) {
        if (assetAmount > _maxDeposit(receiver))
            revert ERC4626Base__MaximumAmountExceeded();

        _updateVars();
        shareAmount = _previewDeposit(assetAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
    }

    function _mint(
        uint256 shareAmount,
        address receiver
    ) override internal virtual returns (uint256 assetAmount) {
        if (shareAmount > _maxMint(receiver))
            revert ERC4626Base__MaximumAmountExceeded();

        assetAmount = _previewMint(shareAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
    }

    function _withdraw(
        uint256 assetAmount,
        address receiver,
        address owner
    ) override internal virtual returns (uint256 shareAmount) {
        if (assetAmount > _maxWithdraw(owner))
            revert ERC4626Base__MaximumAmountExceeded();

        shareAmount = _previewWithdraw(assetAmount);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    ) override internal virtual returns (uint256 assetAmount) {
        if (shareAmount > _maxRedeem(owner))
            revert ERC4626Base__MaximumAmountExceeded();

        _updateVars();
        assetAmount = _previewRedeem(shareAmount);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    function _afterDeposit(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) override internal virtual {}

    function _beforeWithdraw(
        address owner,
        uint256 assetAmount,
        uint256 shareAmount
    ) override internal virtual {}

    function _deposit(
        address caller,
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 assetAmountOffset,
        uint256 shareAmountOffset
    ) override internal virtual {
        uint256 assetAmountNet = assetAmount - assetAmountOffset;

        if (assetAmountNet > 0) {
            IERC20(_asset()).safeTransferFrom(
                caller,
                address(this),
                assetAmountNet
            );
        }

        uint256 shareAmountNet = shareAmount - shareAmountOffset;

        if (shareAmountNet > 0) {
            _mint(receiver, shareAmountNet);
        }

        _afterDeposit(receiver, assetAmount, shareAmount);

        emit Deposit(caller, receiver, assetAmount, shareAmount);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 assetAmountOffset,
        uint256 shareAmountOffset
    ) override internal virtual {
        if (caller != owner) {
            uint256 allowance = _allowance(owner, caller);

            if (shareAmount > allowance)
                revert ERC4626Base__AllowanceExceeded();

        unchecked {
            _approve(owner, caller, allowance - shareAmount);
        }
        }

        _beforeWithdraw(owner, assetAmount, shareAmount);

        uint256 shareAmountNet = shareAmount - shareAmountOffset;

        if (shareAmountNet > 0) {
            _burn(owner, shareAmountNet);
        }

        uint256 assetAmountNet = assetAmount - assetAmountOffset;

        if (assetAmountNet > 0) {
            IERC20(_asset()).safeTransfer(receiver, assetAmountNet);
        }

        emit Withdraw(caller, receiver, owner, assetAmount, shareAmount);
    }

    function _handleTradeFees(uint256 premium, uint256 spread) internal view {

    }

    /// @inheritdoc IUnderwriterVault
    function buy(
        address taker,
        uint256 strike,
        uint256 maturity,
        uint256 size
    ) override external returns (uint256 premium) {
        UnderwriterVaultStorage.Layout storage l = UnderwriterVaultStorage.layout();

        // Validate listing
        // Check if not expired
        if (block.timestamp >= maturity) revert Vault__OptionExpired();
        // Check if this listing is supported by the vault. We'll need to restrict it as big moves in spot may result
        // in new listings we may want to support, making FV calculations potentially intractable.
        if (
            !l.supportedMaturities[maturity] &&
            !l.supportedStrikes[strike]
        ) revert Vault__OptionPoolNotSupported();
        // Check if the vault has sufficient funds
        // todo: the amount of available assets can change depending on whether we introduce deadlines
        uint256 availableAssets = l.totalAssets - l.totalLockedSpread - l.totalLocked;
        if (size >= availableAssets) revert Vault__InsufficientFunds();
        // Check if this listing has a pool deployed
        // revert Vault__OptionPoolNotListed();

        // Compute premium and the spread collected
        uint256 spotPrice; // get price from oracle
        uint256 timeToMaturity = maturity - block.timestamp;
        // todo: getVol should return uint
        // todo: implement batched call
        int256 sigma = IVolatilityOracle(ORACLE).getVolatility(
            _asset(),
            spotPrice,
            strike,
            timeToMaturity
        );
        uint256 volAnnualized = uint256(sigma);
        uint256 price = OptionMath.blackScholesPrice(
            spotPrice,
            strike,
            timeToMaturity,
            volAnnualized,
            0,
            l.isCall
        );

        uint256 premium = size * uint256(price);
        // todo: enso / professors function call do compute the spread
        uint256 spread;
        // connect with the corresponding pool to mint shorts + longs

        // Handle the premiums and spread capture generated
        // _handleTradeFees(premium, spread)

        // below code could belong to the _handleTradeFees function
        l.totalLockedSpread += spread;
        uint256 spreadRate = spread / timeToMaturity;
        // todo: we need to update totalLockedSpread before updating the spreadUnlockingRate (!)
        // todo: otherwise there will be an inconsistency and too much spread will be deducted since lastSpreadUpdate
        // todo: call _updateVars()
        l.spreadUnlockingRate += spreadRate;

        l.totalAssets += premium + spread;
        l.totalLocked += size;

        return premium;
    }

    function settle() override external returns (uint256) {
        return 0;
    }

}

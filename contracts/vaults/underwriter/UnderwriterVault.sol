pragma solidity ^0.8.0;

import "./IUnderwriterVault.sol";
import "./UnderwriterVaultStorage.sol";

contract UnderwriterVault is IUnderwriterVault{
    using UnderwriterVaultStorage for UnderwriterVaultStorage.Layout;

    /// @inheritdoc ERC4626BaseInternal
    function _asset() internal view virtual returns (address) {
        return ERC4626BaseStorage.layout().asset;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _totalAssets() internal view virtual returns (uint256) {
        return totalAssets;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToShares(
        uint256 assetAmount
    ) internal view virtual returns (uint256 shareAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            shareAmount = assetAmount;
        } else {
            uint256 totalAssets = _totalAssets();
            if (totalAssets == 0) {
                shareAmount = assetAmount;
            } else {
                shareAmount = (assetAmount * supply) / totalAssets;
            }
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _convertToAssets(
        uint256 shareAmount
    ) internal view virtual returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            assetAmount = shareAmount;
        } else {
            assetAmount = (shareAmount * _totalAssets()) / supply;
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxDeposit(
        address
    ) internal view virtual returns (uint256 maxAssets) {
        maxAssets = type(uint256).max;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxMint(
        address
    ) internal view virtual returns (uint256 maxShares) {
        maxShares = type(uint256).max;
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxWithdraw(
        address owner
    ) internal view virtual returns (uint256 maxAssets) {
        maxAssets = _convertToAssets(_balanceOf(owner));
    }

    /// @inheritdoc ERC4626BaseInternal
    function _maxRedeem(
        address owner
    ) internal view virtual returns (uint256 maxShares) {
        maxShares = _balanceOf(owner);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewDeposit(
        uint256 assetAmount
    ) internal view virtual returns (uint256 shareAmount) {
        shareAmount = _convertToShares(assetAmount);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewMint(
        uint256 shareAmount
    ) internal view virtual returns (uint256 assetAmount) {
        uint256 supply = _totalSupply();

        if (supply == 0) {
            assetAmount = shareAmount;
        } else {
            assetAmount = (shareAmount * _totalAssets() + supply - 1) / supply;
        }
    }

    /// @inheritdoc ERC4626BaseInternal
    function _previewWithdraw(
        uint256 assetAmount
    ) internal view virtual returns (uint256 shareAmount) {
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

    /// @inheritdoc ERC4626BaseInternal
    function _previewRedeem(
        uint256 shareAmount
    ) internal view virtual returns (uint256 assetAmount) {
        assetAmount = _convertToAssets(shareAmount);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _deposit(
        uint256 assetAmount,
        address receiver
    ) internal virtual returns (uint256 shareAmount) {
        if (assetAmount > _maxDeposit(receiver))
            revert ERC4626Base__MaximumAmountExceeded();

        shareAmount = _previewDeposit(assetAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _mint(
        uint256 shareAmount,
        address receiver
    ) internal virtual returns (uint256 assetAmount) {
        if (shareAmount > _maxMint(receiver))
            revert ERC4626Base__MaximumAmountExceeded();

        assetAmount = _previewMint(shareAmount);

        _deposit(msg.sender, receiver, assetAmount, shareAmount, 0, 0);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _withdraw(
        uint256 assetAmount,
        address receiver,
        address owner
    ) internal virtual returns (uint256 shareAmount) {
        if (assetAmount > _maxWithdraw(owner))
            revert ERC4626Base__MaximumAmountExceeded();

        shareAmount = _previewWithdraw(assetAmount);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _redeem(
        uint256 shareAmount,
        address receiver,
        address owner
    ) internal virtual returns (uint256 assetAmount) {
        if (shareAmount > _maxRedeem(owner))
            revert ERC4626Base__MaximumAmountExceeded();

        assetAmount = _previewRedeem(shareAmount);

        _withdraw(msg.sender, receiver, owner, assetAmount, shareAmount, 0, 0);
    }

    /// @inheritdoc ERC4626BaseInternal
    function _afterDeposit(
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount
    ) internal virtual {}

    /// @inheritdoc ERC4626BaseInternal
    function _beforeWithdraw(
        address owner,
        uint256 assetAmount,
        uint256 shareAmount
    ) internal virtual {}

    /// @inheritdoc ERC4626BaseInternal
    function _deposit(
        address caller,
        address receiver,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 assetAmountOffset,
        uint256 shareAmountOffset
    ) internal virtual {
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

    /// @inheritdoc ERC4626BaseInternal
    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assetAmount,
        uint256 shareAmount,
        uint256 assetAmountOffset,
        uint256 shareAmountOffset
    ) internal virtual {
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
    ) external view returns (uint256 premium) {

        // Validate listing
        // Check if this listing has a pool deployed

        // Compute premium and the spread collected


        // Handle the premiums and spread capture generated
        // _handleTradeFees(premium, spread)

        return 0;
    }

    /// @inheritdoc IUnderwriterVault
    function settle() external returns (uint256) {
        return 0;
    }

}

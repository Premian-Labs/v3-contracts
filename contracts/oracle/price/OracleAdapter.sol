// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import {AccessControl, IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";

import {IOracleAdapter} from "./IOracleAdapter.sol";

/// @title Base oracle adapter implementation, which suppoprts access control multi-call and ERC165
/// @notice Most implementations of `IOracleAdapter` will have an internal function that is called in both
///         `addSupportForPairIfNeeded` and `addOrModifySupportForPair`. This oracle is now making this explicit, and
///         implementing these two functions. They remain virtual so that they can be overriden if needed.
/// @notice derived from https://github.com/Mean-Finance/oracles
abstract contract OracleAdapter is AccessControl, IOracleAdapter, Multicall {
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    constructor(address _superAdmin, address[] memory _initialAdmins) {
        // We are setting the super admin role as its own admin so we can transfer it
        _setRoleAdmin(SUPER_ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setupRole(SUPER_ADMIN_ROLE, _superAdmin);

        for (uint256 i = 0; i < _initialAdmins.length; i++) {
            _setupRole(ADMIN_ROLE, _initialAdmins[i]);
        }
    }

    /// @inheritdoc IOracleAdapter
    function isPairAlreadySupported(
        address tokenA,
        address tokenB
    ) public view virtual returns (bool);

    /// @inheritdoc IOracleAdapter
    function addOrModifySupportForPair(
        address _tokenA,
        address _tokenB,
        bytes calldata _data
    ) external virtual {
        _addOrModifySupportForPair(_tokenA, _tokenB, _data);
    }

    /// @inheritdoc IOracleAdapter
    function addSupportForPairIfNeeded(
        address _tokenA,
        address _tokenB,
        bytes calldata _data
    ) external virtual {
        if (isPairAlreadySupported(_tokenA, _tokenB))
            revert Oracle__PairAlreadySupported(_tokenA, _tokenB);

        _addOrModifySupportForPair(_tokenA, _tokenB, _data);
    }

    /// @inheritdoc IOracleAdapter
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        virtual
        override(AccessControl, IOracleAdapter)
        returns (bool)
    {
        return
            _interfaceId == type(IAccessControl).interfaceId ||
            _interfaceId == type(IOracleAdapter).interfaceId ||
            _interfaceId == type(Multicall).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice Add or reconfigures the support for a given pair. This function will let the oracle take some actions
    ///         to configure the pair, in preparation for future quotes. Can be called many times in order to let the oracle
    ///         re-configure for a new context
    /// @dev Will revert if pair cannot be supported. tokenA and tokenB may be passed in either tokenA/tokenB or tokenB/tokenA order
    /// @param tokenA One of the pair's tokens
    /// @param tokenB The other of the pair's tokens
    /// @param data Custom data that the oracle might need to operate
    function _addOrModifySupportForPair(
        address tokenA,
        address tokenB,
        bytes calldata data
    ) internal virtual;
}

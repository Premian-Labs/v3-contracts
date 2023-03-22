// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {ISignatureTransfer} from "../vendor/uniswap/ISignatureTransfer.sol";

library Permit2 {
    address internal constant PERMIT2 =
        address(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    struct Data {
        address permittedToken;
        uint256 permittedAmount;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    function emptyPermit() internal pure returns (Data memory) {
        return
            Data({
                permittedToken: address(0),
                permittedAmount: 0,
                nonce: 0,
                deadline: 0,
                signature: ""
            });
    }

    function permitTransferFrom(
        Permit2.Data memory permit,
        address owner,
        address to,
        uint256 amount
    ) internal {
        ISignatureTransfer(PERMIT2).permitTransferFrom(
            ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({
                    token: permit.permittedToken,
                    amount: permit.permittedAmount
                }),
                nonce: permit.nonce,
                deadline: permit.deadline
            }),
            ISignatureTransfer.SignatureTransferDetails({
                to: to,
                requestedAmount: amount
            }),
            owner,
            permit.signature
        );
    }
}

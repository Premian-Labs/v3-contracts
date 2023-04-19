// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";

import {IFlashLoanCallback} from "../../pool/IFlashLoanCallback.sol";
import {IPool} from "../../pool/IPool.sol";

contract FlashLoanMock is IFlashLoanCallback {
    struct FlashLoan {
        address pool;
        uint256 amount;
    }

    function singleFlashLoan(FlashLoan memory loan, bool repayFull) external {
        IPool(loan.pool).flashLoan(
            loan.amount,
            abi.encode(new FlashLoan[](0), repayFull)
        );
    }

    function multiFlashLoan(FlashLoan[] memory loans) external {
        FlashLoan memory loan = loans[loans.length - 1];

        // Remove last element from array
        assembly {
            mstore(loans, sub(mload(loans), 1))
        }

        IPool(loan.pool).flashLoan(loan.amount, abi.encode(loans, true));
    }

    function premiaFlashLoanCallback(
        address token,
        uint256 amountToRepay,
        bytes memory data
    ) external {
        (FlashLoan[] memory loans, bool repayFull) = abi.decode(
            data,
            (FlashLoan[], bool)
        );

        if (loans.length > 0) {
            FlashLoan memory nextLoan = loans[loans.length - 1];

            // Remove last element from array
            assembly {
                mstore(loans, sub(mload(loans), 1))
            }

            IPool(nextLoan.pool).flashLoan(
                nextLoan.amount,
                abi.encode(loans, true)
            );
        }

        // Logic can be inserted here to do something with the funds, before repaying all flash loans

        IERC20(token).transfer(
            msg.sender,
            repayFull ? amountToRepay : amountToRepay - 1
        );
    }
}

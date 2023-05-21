// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC3156FlashBorrower} from "@solidstate/contracts/interfaces/IERC3156FlashBorrower.sol";

import {IPool} from "../../pool/IPool.sol";

contract FlashLoanMock is IERC3156FlashBorrower {
    bytes32 internal constant FLASH_LOAN_CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    struct FlashLoan {
        address pool;
        address token;
        uint256 amount;
    }

    function singleFlashLoan(FlashLoan memory loan, bool repayFull) external {
        IPool(loan.pool).flashLoan(this, loan.token, loan.amount, abi.encode(new FlashLoan[](0), repayFull));
    }

    function multiFlashLoan(FlashLoan[] memory loans) external {
        FlashLoan memory loan = loans[loans.length - 1];

        // Remove last element from array
        assembly {
            mstore(loans, sub(mload(loans), 1))
        }

        IPool(loan.pool).flashLoan(this, loan.token, loan.amount, abi.encode(loans, true));
    }

    function onFlashLoan(
        address,
        address token,
        uint256 amount,
        uint256 fee,
        bytes memory data
    ) external returns (bytes32) {
        (FlashLoan[] memory loans, bool repayFull) = abi.decode(data, (FlashLoan[], bool));

        if (loans.length > 0) {
            FlashLoan memory nextLoan = loans[loans.length - 1];

            // Remove last element from array
            assembly {
                mstore(loans, sub(mload(loans), 1))
            }

            IPool(nextLoan.pool).flashLoan(this, nextLoan.token, nextLoan.amount, abi.encode(loans, true));
        } else {
            // Logic can be inserted here to do something with the funds, before repaying all flash loans
        }

        uint256 amountToRepay = amount + fee;
        IERC20(token).transfer(msg.sender, repayFull ? amountToRepay : amountToRepay - 1);

        return FLASH_LOAN_CALLBACK_SUCCESS;
    }
}

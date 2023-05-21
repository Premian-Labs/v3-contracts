// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";

import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC1155BaseInternal} from "@solidstate/contracts/token/ERC1155/base/IERC1155BaseInternal.sol";

import {ZERO, ONE, TWO} from "contracts/libraries/Constants.sol";
import {Position} from "contracts/libraries/Position.sol";

import {IPoolBase} from "contracts/pool/IPoolBase.sol";
import {IPoolInternal} from "contracts/pool/IPoolInternal.sol";
import {PoolStorage} from "contracts/pool/PoolStorage.sol";

import {DeployTest} from "../Deploy.t.sol";

abstract contract PoolTransferTest is DeployTest {
    function test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_SameOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.lp, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.lp,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), (protocolFees / 4) * 3);
        assertEq(pool.getClaimableFees(newKey), protocolFees / 4);
    }

    function test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_NewOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.trader,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), (protocolFees / 4) * 3);
        assertEq(pool.getClaimableFees(newKey), protocolFees / 4);
    }

    function test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_SameOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.lp, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.lp,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.getClaimableFees(newKey), protocolFees);
    }

    function test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_NewOperator() public {
        trade(1 ether, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        Position.Key memory newKey = Position.Key({
            owner: users.trader,
            operator: users.trader,
            lower: posKey.lower,
            upper: posKey.upper,
            orderType: posKey.orderType
        });

        uint256 protocolFees = pool.protocolFees();
        assertEq(pool.getClaimableFees(posKey), 0);
        assertEq(pool.getClaimableFees(newKey), protocolFees);
    }

    function test_transferPosition_Success_OnPartialTransfer_NewOwner_SameOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        uint256 transferAmount = 200 ether;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, posKey.operator, ud(transferAmount));

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize - transferAmount);
        assertEq(pool.balanceOf(users.trader, tokenId()), transferAmount);
    }

    function test_transferPosition_Success_OnPartialTransfer_NewOwner_NewOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        uint256 transferAmount = 200 ether;

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(transferAmount));

        assertEq(pool.balanceOf(users.lp, tokenId()), depositSize - transferAmount);
        assertEq(pool.balanceOf(users.trader, tokenId()), 0);

        posKey.operator = users.trader;
        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), transferAmount);
    }

    function test_transferPosition_Success_OnFullTransfer_NewOwner_SameOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, posKey.operator, ud(depositSize));

        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), depositSize);
    }

    function test_transferPosition_Success_OnFullTransfer_NewOwner_NewOperator() public {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        vm.startPrank(users.lp);
        pool.transferPosition(posKey, users.trader, users.trader, ud(depositSize));

        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), 0);

        posKey.operator = users.trader;
        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), depositSize);
    }

    function test_transferPosition_RevertIf_NotOperator() public {
        deposit(1000 ether);

        vm.startPrank(users.trader);

        vm.expectRevert(abi.encodeWithSelector(IPoolInternal.Pool__OperatorNotAuthorized.selector, users.trader));
        pool.transferPosition(posKey, users.trader, posKey.operator, ud(200 ether));
    }

    function test_transferPosition_RevertIf_SameOwner_SameOperator() public {
        deposit(1000 ether);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__InvalidTransfer.selector);
        pool.transferPosition(posKey, users.lp, users.lp, ud(200 ether));
    }

    function test_transferPosition_RevertIf_SizeIsZero() public {
        deposit(1000 ether);

        vm.startPrank(users.lp);

        vm.expectRevert(IPoolInternal.Pool__ZeroSize.selector);
        pool.transferPosition(posKey, users.trader, users.lp, ud(0));
    }

    function test_transferPosition_RevertIf_NotEnoughTokensToTransfer() public {
        deposit(1000 ether);

        vm.startPrank(users.lp);

        vm.expectRevert(
            abi.encodeWithSelector(IPoolInternal.Pool__NotEnoughTokens.selector, 1000 ether, 1000 ether + 1)
        );
        pool.transferPosition(posKey, users.trader, users.lp, ud(1000 ether + 1));
    }

    function test_safeTransferFrom_TransferLongToken() public {
        trade(1 ether, true);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.LONG, transferAmount, "");

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18 - transferAmount);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), transferAmount);
    }

    function test_safeTransferFrom_TransferShortToken() public {
        trade(1 ether, false);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.SHORT), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.SHORT, transferAmount, "");

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 1e18 - transferAmount);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.SHORT), transferAmount);
    }

    function test_safeTransferFrom_TransferNonPositionToken_FromApprovedAddress() public {
        trade(1 ether, true);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.setApprovalForAll(users.otherTrader, true);

        vm.prank(users.otherTrader);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.LONG, transferAmount, "");

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18 - transferAmount);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), transferAmount);
    }

    function test_safeTransferFrom_RevertIf_TransferLpPosition() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        vm.prank(users.lp);
        vm.expectRevert(IPoolBase.Pool__UseTransferPositionToTransferLPTokens.selector);
        pool.safeTransferFrom(users.lp, users.trader, tokenId(), 200e18, "");
    }

    function test_safeTransferFrom_RevertIf_NotApproved() public {
        trade(1 ether, false);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.otherTrader);
        vm.expectRevert(IERC1155BaseInternal.ERC1155Base__NotOwnerOrApproved.selector);
        pool.safeTransferFrom(users.trader, users.otherTrader, PoolStorage.SHORT, transferAmount, "");
    }
}

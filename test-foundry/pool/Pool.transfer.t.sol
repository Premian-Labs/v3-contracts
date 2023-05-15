// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

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
    function _trade(bool isCall, bool isBuy) internal {
        if (isBuy) posKey.orderType = Position.OrderType.CS;

        deposit(1 ether);

        UD60x18 tradeSize = ud(1 ether);

        (uint256 totalPremium, ) = pool.getQuoteAMM(
            users.trader,
            tradeSize,
            isBuy
        );

        address poolToken = getPoolToken(isCall);

        uint256 mintAmount = isBuy
            ? totalPremium
            : scaleDecimals(poolKey.strike, isCall);

        vm.startPrank(users.trader);
        deal(poolToken, users.trader, mintAmount);
        IERC20(poolToken).approve(address(router), mintAmount);

        pool.trade(
            tradeSize,
            isBuy,
            isBuy
                ? totalPremium + totalPremium / 10
                : totalPremium - totalPremium / 10,
            address(0)
        );
        vm.stopPrank();
    }

    function _test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_SameOperator(
        bool isCall
    ) internal {
        _trade(isCall, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.lp,
            users.trader,
            ud(transferAmount)
        );

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

    function test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_SameOperator()
        public
    {
        _test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_SameOperator(
            poolKey.isCallPool
        );
    }

    function _test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_NewOperator(
        bool isCall
    ) internal {
        _trade(isCall, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId()) / 4;

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.trader,
            users.trader,
            ud(transferAmount)
        );

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

    function test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_NewOperator()
        public
    {
        _test_transferPosition_UpdateClaimableFees_OnPartialTransfer_NewOwner_NewOperator(
            poolKey.isCallPool
        );
    }

    function _test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_SameOperator(
        bool isCall
    ) internal {
        _trade(isCall, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.lp,
            users.trader,
            ud(transferAmount)
        );

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

    function test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_SameOperator()
        public
    {
        _test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_SameOperator(
            poolKey.isCallPool
        );
    }

    function _test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_NewOperator(
        bool isCall
    ) internal {
        _trade(isCall, true);
        uint256 transferAmount = pool.balanceOf(posKey.operator, tokenId());

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.trader,
            users.trader,
            ud(transferAmount)
        );

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

    function test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_NewOperator()
        public
    {
        _test_transferPosition_UpdateClaimableFees_OnFullTransfer_NewOwner_NewOperator(
            poolKey.isCallPool
        );
    }

    function test_transferPosition_Success_OnPartialTransfer_NewOwner_SameOperator()
        public
    {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        uint256 transferAmount = 200 ether;

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.trader,
            posKey.operator,
            ud(transferAmount)
        );

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize - transferAmount
        );
        assertEq(pool.balanceOf(users.trader, tokenId()), transferAmount);
    }

    function test_transferPosition_Success_OnPartialTransfer_NewOwner_NewOperator()
        public
    {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        uint256 transferAmount = 200 ether;

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.trader,
            users.trader,
            ud(transferAmount)
        );

        assertEq(
            pool.balanceOf(users.lp, tokenId()),
            depositSize - transferAmount
        );
        assertEq(pool.balanceOf(users.trader, tokenId()), 0);

        posKey.operator = users.trader;
        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), transferAmount);
    }

    function test_transferPosition_Success_OnFullTransfer_NewOwner_SameOperator()
        public
    {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.trader,
            posKey.operator,
            ud(depositSize)
        );

        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), depositSize);
    }

    function test_transferPosition_Success_OnFullTransfer_NewOwner_NewOperator()
        public
    {
        uint256 depositSize = 1000 ether;

        posKey.orderType = Position.OrderType.CS;
        deposit(depositSize);

        vm.startPrank(users.lp);
        pool.transferPosition(
            posKey,
            users.trader,
            users.trader,
            ud(depositSize)
        );

        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), 0);

        posKey.operator = users.trader;
        assertEq(pool.balanceOf(users.lp, tokenId()), 0);
        assertEq(pool.balanceOf(users.trader, tokenId()), depositSize);
    }

    function test_transferPosition_RevertIf_NotOperator() public {
        deposit(1000 ether);

        vm.startPrank(users.trader);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPoolInternal.Pool__OperatorNotAuthorized.selector,
                users.trader
            )
        );
        pool.transferPosition(
            posKey,
            users.trader,
            posKey.operator,
            ud(200 ether)
        );
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
            abi.encodeWithSelector(
                IPoolInternal.Pool__NotEnoughTokens.selector,
                1000 ether,
                1000 ether + 1
            )
        );
        pool.transferPosition(
            posKey,
            users.trader,
            users.lp,
            ud(1000 ether + 1)
        );
    }

    function _test_safeTransferFrom_TransferLongToken(bool isCall) internal {
        _trade(isCall, true);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.safeTransferFrom(
            users.trader,
            users.otherTrader,
            PoolStorage.LONG,
            transferAmount,
            ""
        );

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            1e18 - transferAmount
        );
        assertEq(
            pool.balanceOf(users.otherTrader, PoolStorage.LONG),
            transferAmount
        );
    }

    function test_safeTransferFrom_TransferLongToken() public {
        _test_safeTransferFrom_TransferLongToken(poolKey.isCallPool);
    }

    function _test_safeTransferFrom_TransferShortToken(bool isCall) internal {
        _trade(isCall, false);

        assertEq(pool.balanceOf(users.trader, PoolStorage.SHORT), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.SHORT), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.safeTransferFrom(
            users.trader,
            users.otherTrader,
            PoolStorage.SHORT,
            transferAmount,
            ""
        );

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.SHORT),
            1e18 - transferAmount
        );
        assertEq(
            pool.balanceOf(users.otherTrader, PoolStorage.SHORT),
            transferAmount
        );
    }

    function test_safeTransferFrom_TransferShortToken() public {
        _test_safeTransferFrom_TransferShortToken(poolKey.isCallPool);
    }

    function _test_safeTransferFrom_TransferNonPositionToken_FromApprovedAddress(
        bool isCall
    ) internal {
        _trade(isCall, true);

        assertEq(pool.balanceOf(users.trader, PoolStorage.LONG), 1e18);
        assertEq(pool.balanceOf(users.otherTrader, PoolStorage.LONG), 0);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.trader);
        pool.setApprovalForAll(users.otherTrader, true);

        vm.prank(users.otherTrader);
        pool.safeTransferFrom(
            users.trader,
            users.otherTrader,
            PoolStorage.LONG,
            transferAmount,
            ""
        );

        assertEq(
            pool.balanceOf(users.trader, PoolStorage.LONG),
            1e18 - transferAmount
        );
        assertEq(
            pool.balanceOf(users.otherTrader, PoolStorage.LONG),
            transferAmount
        );
    }

    function test_safeTransferFrom_TransferNonPositionToken_FromApprovedAddress()
        public
    {
        _test_safeTransferFrom_TransferNonPositionToken_FromApprovedAddress(
            poolKey.isCallPool
        );
    }

    function test_safeTransferFrom_RevertIf_TransferLpPosition() public {
        posKey.orderType = Position.OrderType.CS;
        deposit(1000 ether);

        vm.prank(users.lp);
        vm.expectRevert(
            IPoolBase.Pool__UseTransferPositionToTransferLPTokens.selector
        );
        pool.safeTransferFrom(users.lp, users.trader, tokenId(), 200e18, "");
    }

    function _test_safeTransferFrom_RevertIf_NotApproved(bool isCall) internal {
        _trade(isCall, false);

        uint256 transferAmount = 0.3e18;

        vm.prank(users.otherTrader);
        vm.expectRevert(
            IERC1155BaseInternal.ERC1155Base__NotOwnerOrApproved.selector
        );
        pool.safeTransferFrom(
            users.trader,
            users.otherTrader,
            PoolStorage.SHORT,
            transferAmount,
            ""
        );
    }

    function test_safeTransferFrom_RevertIf_NotApproved() public {
        _test_safeTransferFrom_RevertIf_NotApproved(poolKey.isCallPool);
    }
}
